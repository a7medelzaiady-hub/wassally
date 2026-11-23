import { afterEach, describe, expect, it, vi } from "vitest";

vi.mock("jose", () => ({
  createRemoteJWKSet: () => () => ({}),
  // الـtoken في الاختبار = uid (عشان نجرب عميل ومندوب ومستخدم غريب).
  jwtVerify: async (token: string) => ({
    payload: { sub: token, auth_time: Math.floor(Date.now() / 1000), firebase: { sign_in_provider: "google.com" } },
  }),
  importPKCS8: async () => ({}),
  SignJWT: class {
    setProtectedHeader() { return this; }
    setIssuer() { return this; }
    setAudience() { return this; }
    setIssuedAt() { return this; }
    setExpirationTime() { return this; }
    async sign() { return "fake-service-jwt"; }
  },
}));

import worker, { adminNoticeBlocker, adminNoticeMessage } from "../src/index";

const prefix = "projects/wasally-test/databases/(default)/documents/";
const env = {
  FIREBASE_PROJECT_ID: "wasally-test",
  FIREBASE_SERVICE_ACCOUNT_EMAIL: "test@wasally-test.iam.gserviceaccount.com",
  FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY: "mock-key",
  APP_CHECK_MODE: "off",
} as never;

function enc(v: unknown): unknown {
  if (Array.isArray(v)) return { arrayValue: { values: v.map(enc) } };
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (typeof v === "string") return { stringValue: v };
  if (typeof v === "boolean") return { booleanValue: v };
  if (typeof v === "number") return { doubleValue: v };
  return { nullValue: null };
}
const fields = (m: Record<string, unknown>) => Object.fromEntries(Object.entries(m).map(([k, v]) => [k, enc(v)]));

type Docs = Record<string, Record<string, unknown> | undefined>;
let commits: any[] = [];
let fcm: any[] = [];
let commitStatus = 200;
function firebase(docs: Docs) {
  commits = [];
  fcm = [];
  return vi.spyOn(globalThis, "fetch").mockImplementation(async (resource, init) => {
    const url = String(resource);
    if (url.includes("oauth2.googleapis.com/token")) return Response.json({ access_token: "t", expires_in: 3600 });
    if (url.includes("accounts:lookup")) {
      const uid = JSON.parse(String(init?.body)).localId[0];
      return Response.json({ users: [{ localId: uid, validSince: "1", disabled: false }] });
    }
    if (url.endsWith("/documents:commit")) {
      const body = JSON.parse(String(init?.body));
      commits.push(body);
      if (commitStatus !== 200) return new Response("conflict", { status: commitStatus });
      return Response.json({ writeResults: [] });
    }
    if (url.includes("fcm.googleapis.com/")) {
      fcm.push(JSON.parse(String(init?.body)));
      return Response.json({ name: "m" });
    }
    if (url.includes("firestore.googleapis.com/")) {
      const path = decodeURIComponent(url.split("/documents/")[1]);
      const d = docs[path];
      if (d) return Response.json({ name: prefix + path, fields: fields(d), updateTime: "2026-11-20T10:00:00.000000Z" });
      return new Response("not found", { status: 404 });
    }
    throw Error("Unexpected request: " + url);
  });
}
afterEach(() => vi.restoreAllMocks());


const notify = (uid: string, kind: string, id: string) => worker.fetch(new Request("https://w.test/v1/notify-admins", {
  method: "POST", headers: { Authorization: "Bearer " + uid, "Content-Type": "application/json" },
  body: JSON.stringify({ kind, id }),
}), env);
const fresh = () => new Date(Date.now() - 30_000);

describe("POST /v1/notify-admins", () => {
  it("join request by its owner: records once and pushes to the admins topic without personal data", async () => {
    commitStatus = 200;
    firebase({ "role_requests/u1_courier": { userId: "u1", type: "courier", status: "pending", name: "Secret Name", phone: "010", createdAt: fresh() } });
    const res = await notify("u1", "join_request", "u1_courier");
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ sent: true });
    expect(commits[0].writes[0].currentDocument).toEqual({ exists: false });
    expect(commits[0].writes[0].update.name).toContain("adminNotices/join_request_u1_courier");
    expect(fcm).toHaveLength(1);
    expect(fcm[0].message.topic).toBe("admins");
    expect(JSON.stringify(fcm[0])).not.toContain("Secret Name");
    expect(JSON.stringify(fcm[0])).not.toContain("010");
  });

  it("second call for the same document does not push again", async () => {
    commitStatus = 409;
    firebase({ "role_requests/u1_courier": { userId: "u1", type: "courier", status: "pending", createdAt: fresh() } });
    const res = await notify("u1", "join_request", "u1_courier");
    expect(await res.json()).toMatchObject({ sent: false });
    expect(fcm).toHaveLength(0);
    commitStatus = 200;
  });

  it("refuses someone else's request, old documents and unknown kinds", async () => {
    firebase({
      "role_requests/u1_courier": { userId: "u1", type: "courier", status: "pending", createdAt: fresh() },
      "role_requests/u2_courier": { userId: "u2", type: "courier", status: "pending", createdAt: new Date(Date.now() - 3600_000) },
    });
    expect((await notify("u9", "join_request", "u1_courier")).status).toBe(403);
    expect((await notify("u2", "join_request", "u2_courier")).status).toBe(409);
    expect((await notify("u1", "spam", "u1_courier")).status).toBe(400);
    expect((await notify("u1", "join_request", "../x")).status).toBe(400);
    expect(fcm).toHaveLength(0);
  });

  it("delivery issue: only the courier who created it", async () => {
    firebase({
      "delivery_issues/i1": {
        createdBy: "c1", status: "return_to_store", createdAt: fresh(),
        orderId: "o1", customerId: "u1", note: "private return details",
      },
      "users/u1": { fcmTokens: ["customer-device"] },
    });
    expect((await notify("c2", "delivery_issue", "i1")).status).toBe(403);
    expect((await notify("c1", "delivery_issue", "i1")).status).toBe(200);
    expect(fcm).toHaveLength(2);
    expect(fcm).toContainEqual({
      message: expect.objectContaining({
        token: "customer-device", data: { type: "order_update", orderId: "o1" },
      }),
    });
    expect(JSON.stringify(fcm)).not.toContain("private return details");
  });
});

describe("admin notice helpers", () => {
  it("message text by kind", () => {
    expect(adminNoticeMessage("join_request", "store_owner").message.notification.body).toContain("صاحب محل");
    expect(adminNoticeMessage("delivery_issue", "").message.data.type).toBe("admin_inbox");
  });
  it("blocker rejects not-pending join requests and missing docs", () => {
    expect(adminNoticeBlocker("join_request", "u1_courier", null, "u1")).toBe("not_found");
    expect(adminNoticeBlocker("join_request", "u1_courier", { userId: "u1", status: "approved", createdAt: new Date() }, "u1")).toBe("not_pending");
  });
});
