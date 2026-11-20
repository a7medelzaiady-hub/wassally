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

import worker, { courierDeliveryBlocker, pinDeliveryUpdate } from "../src/index";
import { deriveDeliveryPin, equalPin } from "../src/delivery_pin";

const SECRET = "test-delivery-secret";
const prefix = "projects/wasally-test/databases/(default)/documents/";
const env = {
  FIREBASE_PROJECT_ID: "wasally-test",
  FIREBASE_SERVICE_ACCOUNT_EMAIL: "test@wasally-test.iam.gserviceaccount.com",
  FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY: "mock-key",
  APP_CHECK_MODE: "off",
  DELIVERY_PIN_SECRET: SECRET,
} as never;

function enc(v: unknown): unknown {
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (typeof v === "string") return { stringValue: v };
  if (typeof v === "boolean") return { booleanValue: v };
  if (typeof v === "number") return { doubleValue: v };
  return { nullValue: null };
}
const fields = (m: Record<string, unknown>) => Object.fromEntries(Object.entries(m).map(([k, v]) => [k, enc(v)]));

const onTheWay = (over: Record<string, unknown> = {}) => ({
  userId: "cust_1", courierId: "courier_1", status: "on_the_way", ready: true,
  courierArrivedAt: new Date("2026-11-20T10:00:00Z"), deliveryMode: "store",
  deliveryFee: 20, total: 70, ...over,
});

type Docs = Record<string, Record<string, unknown> | undefined>;
let commits: any[] = [];
function firebase(docs: Docs) {
  commits = [];
  return vi.spyOn(globalThis, "fetch").mockImplementation(async (resource, init) => {
    const url = String(resource);
    if (url.includes("oauth2.googleapis.com/token")) return Response.json({ access_token: "t", expires_in: 3600 });
    if (url.includes("accounts:lookup")) {
      const uid = JSON.parse(String(init?.body)).localId[0];
      return Response.json({ users: [{ localId: uid, validSince: "1", disabled: false }] });
    }
    if (url.endsWith("/documents:commit")) {
      commits.push(JSON.parse(String(init?.body)));
      return Response.json({ writeResults: [] });
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

const getPin = (uid: string, id = "o1") => worker.fetch(new Request(`https://w.test/v1/orders/${id}/delivery-pin`, {
  method: "GET", headers: { Authorization: "Bearer " + uid },
}), env);
const deliver = (uid: string, pin: unknown, id = "o1") => worker.fetch(new Request(`https://w.test/v1/orders/${id}/deliver`, {
  method: "POST", headers: { Authorization: "Bearer " + uid, "Content-Type": "application/json" },
  body: JSON.stringify({ pin }),
}), env);
const wrongOf = (pin: string) => String((Number(pin) + 1) % 10000).padStart(4, "0");

describe("delivery PIN derivation", () => {
  it("is 4 digits, stable per order, different across orders and secrets", async () => {
    const a = await deriveDeliveryPin("o1", SECRET);
    expect(a).toMatch(/^[0-9]{4}$/);
    expect(await deriveDeliveryPin("o1", SECRET)).toBe(a);
    const others = await Promise.all(["o2", "o3", "o4", "o5"].map((id) => deriveDeliveryPin(id, SECRET)));
    expect(others.some((p) => p !== a)).toBe(true);
    expect(await deriveDeliveryPin("o1", "other-secret")).not.toBe(a);
    expect(equalPin(a, a)).toBe(true);
    expect(equalPin(a, wrongOf(a))).toBe(false);
    expect(equalPin("12a4", "12a4")).toBe(false);
  });
});

describe("GET /v1/orders/:id/delivery-pin", () => {
  it("returns the PIN only to the order's customer while on the way", async () => {
    firebase({ "orders/o1": onTheWay() });
    const res = await getPin("cust_1");
    expect(res.status).toBe(200);
    expect(((await res.json()) as { pin: string }).pin).toBe(await deriveDeliveryPin("o1", SECRET));
  });
  it("never returns the PIN to the courier or another user", async () => {
    firebase({ "orders/o1": onTheWay() });
    expect((await getPin("courier_1")).status).toBe(403);
    expect((await getPin("someone_else")).status).toBe(403);
  });
  it("is not available before pickup", async () => {
    firebase({ "orders/o1": onTheWay({ status: "preparing" }) });
    const res = await getPin("cust_1");
    expect(res.status).toBe(409);
    expect(((await res.json()) as { code: string }).code).toBe("pin_not_available");
  });
  it("is disabled when the secret is not configured", async () => {
    firebase({ "orders/o1": onTheWay() });
    const res = await worker.fetch(new Request("https://w.test/v1/orders/o1/delivery-pin", {
      headers: { Authorization: "Bearer cust_1" },
    }), { ...(env as object), DELIVERY_PIN_SECRET: undefined } as never);
    expect(res.status).toBe(503);
  });
});

describe("POST /v1/orders/:id/deliver", () => {
  it("store courier + correct PIN: order delivered with stamps and history, atomically", async () => {
    firebase({ "orders/o1": onTheWay(), "couriers/courier_1": { active: true } });
    const pin = await deriveDeliveryPin("o1", SECRET);
    const res = await deliver("courier_1", pin);
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ delivered: true });
    expect(commits).toHaveLength(1);
    const [orderWrite, history] = commits[0].writes;
    expect(orderWrite.update.name).toBe(prefix + "orders/o1");
    expect(orderWrite.currentDocument).toEqual({ updateTime: "2026-11-20T10:00:00.000000Z" });
    expect(orderWrite.update.fields).toMatchObject({
      status: { stringValue: "delivered" }, deliveredBy: { stringValue: "courier_1" },
      collectedAmount: { integerValue: "70" }, courierEarning: { integerValue: "20" },
    });
    const stamped = orderWrite.updateTransforms.map((t: any) => t.fieldPath).sort();
    expect(stamped).toEqual(["customerConfirmedAt", "customerDeliveryReportedAt", "deliveredAt", "deliveryPinVerifiedAt"].sort());
    expect(history.update.name).toBe(prefix + "orders/o1/statusHistory/delivered");
  });

  it("external courier + correct PIN: customer confirmation recorded, cash settlement still pending", async () => {
    firebase({ "orders/o1": onTheWay({ deliveryMode: "external" }), "couriers/courier_1": { active: true } });
    const res = await deliver("courier_1", await deriveDeliveryPin("o1", SECRET));
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ delivered: false, confirmed: true });
    const w = commits[0].writes[0];
    expect(w.update.fields.status).toBeUndefined();
    expect(w.updateMask.fieldPaths).toEqual(["customerDeliveryReportedBy"]);
    expect(w.updateTransforms.map((t: any) => t.fieldPath)).toContain("customerConfirmedAt");
    expect(commits[0].writes).toHaveLength(1);
  });

  it("correct PIN also cleans special-request attachments (voice) in the same call", async () => {
    // specialRequest كـ map محتاج encoding خاص، فبنعمل mock مخصوص هنا.
    commits = [];
    const orderFields = {
      ...fields(onTheWay()),
      specialRequest: { mapValue: { fields: { text: { stringValue: "x" }, voiceBase64: { stringValue: "AAAA" } } } },
    };
    vi.spyOn(globalThis, "fetch").mockImplementation(async (resource, init) => {
      const url = String(resource);
      if (url.includes("oauth2.googleapis.com/token")) return Response.json({ access_token: "t", expires_in: 3600 });
      if (url.includes("accounts:lookup")) {
        const uid = JSON.parse(String(init?.body)).localId[0];
        return Response.json({ users: [{ localId: uid, validSince: "1", disabled: false }] });
      }
      if (url.endsWith("/documents:commit")) { commits.push(JSON.parse(String(init?.body))); return Response.json({ writeResults: [] }); }
      const path = decodeURIComponent(url.split("/documents/")[1] ?? "");
      if (path === "orders/o1") return Response.json({ name: prefix + path, fields: orderFields, updateTime: "2026-11-20T10:00:00.000000Z" });
      if (path === "couriers/courier_1") return Response.json({ name: prefix + path, fields: fields({ active: true }) });
      return new Response("not found", { status: 404 });
    });
    const res = await deliver("courier_1", await deriveDeliveryPin("o1", SECRET));
    expect(res.status).toBe(200);
    expect(commits).toHaveLength(2);
    const cleanup = commits[1].writes[0];
    expect(cleanup.updateMask).toEqual({ fieldPaths: ["specialRequest"] });
    const sr = cleanup.update.fields.specialRequest.mapValue.fields;
    expect(sr.voiceBase64).toBeUndefined();
    expect(sr.cleanupStatus).toEqual({ stringValue: "deleted" });
  });

  it("wrong PIN: counts the attempt, does not touch the order", async () => {
    firebase({ "orders/o1": onTheWay(), "couriers/courier_1": { active: true }, "deliveryPinAttempts/o1": { attempts: 1 } });
    const res = await deliver("courier_1", wrongOf(await deriveDeliveryPin("o1", SECRET)));
    expect(res.status).toBe(400);
    expect(await res.json()).toMatchObject({ code: "pin_wrong" });
    expect(commits).toHaveLength(1);
    expect(commits[0].writes).toHaveLength(1);
    expect(commits[0].writes[0].update.name).toBe(prefix + "deliveryPinAttempts/o1");
    expect(commits[0].writes[0].update.fields.attempts).toEqual({ integerValue: "2" });
    expect(commits[0].writes[0].currentDocument).toEqual({ updateTime: "2026-11-20T10:00:00.000000Z" });
  });

  it("5th wrong PIN locks and flags the order for admin; later attempts (even correct) are refused", async () => {
    firebase({ "orders/o1": onTheWay(), "couriers/courier_1": { active: true }, "deliveryPinAttempts/o1": { attempts: 4 } });
    const pin = await deriveDeliveryPin("o1", SECRET);
    const res = await deliver("courier_1", wrongOf(pin));
    expect(res.status).toBe(423);
    expect(await res.json()).toMatchObject({ code: "pin_locked" });
    const [attemptsW, orderW] = commits[0].writes;
    expect(attemptsW.update.fields.locked).toEqual({ booleanValue: true });
    expect(orderW.update.name).toBe(prefix + "orders/o1");
    expect(orderW.updateMask).toEqual({ fieldPaths: [] });
    expect(orderW.updateTransforms[0].fieldPath).toBe("deliveryPinLockedAt");

    vi.restoreAllMocks();
    firebase({ "orders/o1": onTheWay(), "couriers/courier_1": { active: true }, "deliveryPinAttempts/o1": { attempts: 5, locked: true } });
    const again = await deliver("courier_1", pin);
    expect(again.status).toBe(423);
    expect(commits).toHaveLength(0);
  });

  it("refuses another courier, an inactive courier, a non-courier and malformed PINs without writing", async () => {
    firebase({ "orders/o1": onTheWay({ courierId: "courier_2" }), "couriers/courier_1": { active: true } });
    const pin = await deriveDeliveryPin("o1", SECRET);
    expect((await deliver("courier_1", pin)).status).toBe(409);
    vi.restoreAllMocks();
    firebase({ "orders/o1": onTheWay(), "couriers/courier_1": { active: false } });
    expect((await deliver("courier_1", pin)).status).toBe(403);
    vi.restoreAllMocks();
    firebase({ "orders/o1": onTheWay() });
    expect((await deliver("courier_1", pin)).status).toBe(403);
    expect((await deliver("cust_1", pin)).status).toBe(403);
    vi.restoreAllMocks();
    firebase({ "orders/o1": onTheWay(), "couriers/courier_1": { active: true } });
    for (const bad of ["12", "12345", 1234, "abcd", null]) {
      expect((await deliver("courier_1", bad)).status).toBe(400);
    }
    expect(commits).toHaveLength(0);
  });

  it("replay after delivery is refused (already confirmed)", async () => {
    firebase({ "orders/o1": onTheWay({ status: "delivered", customerConfirmedAt: new Date() }), "couriers/courier_1": { active: true } });
    expect((await deliver("courier_1", await deriveDeliveryPin("o1", SECRET))).status).toBe(409);
    expect(commits).toHaveLength(0);
  });
});

describe("pure helpers", () => {
  it("courierDeliveryBlocker mirrors the old delivery-report preconditions", () => {
    expect(courierDeliveryBlocker(onTheWay(), "courier_1")).toBeNull();
    expect(courierDeliveryBlocker(onTheWay({ ready: false }), "courier_1")).not.toBeNull();
    expect(courierDeliveryBlocker(onTheWay({ courierArrivedAt: null }), "courier_1")).not.toBeNull();
    expect(courierDeliveryBlocker(onTheWay({ activeDeliveryIssueId: "i1" }), "courier_1")).not.toBeNull();
    expect(courierDeliveryBlocker(onTheWay({ deliveryMode: "x" }), "courier_1")).not.toBeNull();
  });
  it("pinDeliveryUpdate uses final fee and verified total when present", () => {
    const now = new Date();
    const u = pinDeliveryUpdate(onTheWay({ finalDeliveryFee: 15, verifiedTotal: 65 }), "courier_1", now);
    expect(u).toMatchObject({ status: "delivered", courierEarning: 15, collectedAmount: 65, deliveredBy: "courier_1" });
  });
});
