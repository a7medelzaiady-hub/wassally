import { afterEach, expect, it, vi } from "vitest";

vi.mock("jose", () => ({
  createRemoteJWKSet: () => () => ({}),
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
    async sign() { return "commission-test-token"; }
  },
}));

import worker from "../src/index";

const env = {
  FIREBASE_PROJECT_ID: "wasally-test",
  FIREBASE_SERVICE_ACCOUNT_EMAIL: "test@wasally-test.iam.gserviceaccount.com",
  FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY: "mock-key",
  APP_CHECK_MODE: "off",
  REFERRAL_DELIVERY_ENABLED: "true",
} as never;

const root = "projects/wasally-test/databases/(default)/documents/";
const updateTime = "2026-01-01T00:00:00Z";
const str = (stringValue: string) => ({ stringValue });
const int = (value: number) => ({ integerValue: String(value) });

function simulate() {
  const path = "referral_commission_settlements/5-store-invoice-1";
  const docs: Record<string, Record<string, unknown>> = {
    "admins/admin": {},
    "storeOwners/owner": { storeId: str("store"), active: { booleanValue: true } },
    "referral_balances/owner": { commissionDiscountMinor: int(2000) },
  };
  let commits = 0;
  vi.spyOn(globalThis, "fetch").mockImplementation(async (resource, init) => {
    const url = String(resource);
    if (url.includes("oauth2.googleapis.com/token")) {
      return Response.json({ access_token: "t", expires_in: 3600 });
    }
    if (url.includes("accounts:lookup")) {
      const uid = JSON.parse(String(init?.body)).localId[0];
      return Response.json({ users: [{ localId: uid, validSince: "1", disabled: false }] });
    }
    if (url.endsWith(":commit")) {
      const [verify, record, credit] = JSON.parse(String(init?.body)).writes;
      expect(verify).toEqual({
        verify: root + "storeOwners/owner", currentDocument: { updateTime },
      });
      expect(record.update.name).toBe(root + path);
      expect(record.currentDocument).toEqual({ exists: false });
      expect(credit).toEqual({
        transform: {
          document: root + "referral_balances/owner",
          fieldTransforms: [{ fieldPath: "commissionDiscountMinor", increment: int(-2000) }],
        },
        currentDocument: { updateTime },
      });
      if (docs[path]) return new Response(null, { status: 409 });
      docs[path] = record.update.fields;
      commits++;
      return Response.json({ writeResults: [] });
    }
    const documentPath = url.split("/documents/")[1];
    const fields = docs[documentPath];
    return fields
      ? Response.json({ name: root + documentPath, fields, updateTime })
      : new Response(null, { status: 404 });
  });
  return () => commits;
}

function settle(actor: string, changes: Record<string, unknown> = {}) {
  return worker.fetch(new Request("https://worker.test/v1/referrals/commissions", {
    method: "POST",
    headers: { Authorization: `Bearer ${actor}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      ownerUid: "owner", storeId: "store", reference: "invoice-1", dueMinor: 4500,
      ...changes,
    }),
  }), env);
}

afterEach(() => vi.restoreAllMocks());

it("authorizes admin settlement and debits the credit only once for the same reference", async () => {
  const commits = simulate();
  expect((await settle("owner")).status).toBe(403);
  expect((await settle("admin", { storeId: "other-store" })).status).toBe(409);

  const settled = { dueMinor: 4500, discountMinor: 2000, payableMinor: 2500 };
  const first = await settle("admin");
  expect(first.status).toBe(200);
  expect(await first.json()).toEqual(settled);
  const replay = await settle("admin");
  expect(replay.status).toBe(200);
  expect(await replay.json()).toEqual(settled);
  expect((await settle("admin", { dueMinor: 5000 })).status).toBe(409);
  expect(commits()).toBe(1);
});

it.each(["cancelled", "delivered"])("reconciles a %s points order once", async (status) => {
  const orderPath = "orders/points-order";
  const redemptionPath = "referral_redemptions/points-order";
  const source = {
    storeId: str("store"), discountMinor: int(500),
    points: int(20), status: str("reserved"),
  };
  const docs: Record<string, Record<string, unknown>> = {
    "admins/admin": {}, "admins/other-admin": {},
    [orderPath]: { userId: str("customer"), storeId: str("store"),
      referralDiscountMinor: int(500), status: str(status) },
    [redemptionPath]: source,
  };
  const commits: unknown[][] = [];
  vi.spyOn(globalThis, "fetch").mockImplementation(async (resource, init) => {
    const url = String(resource);
    if (url.includes("oauth2.googleapis.com/token"))
      return Response.json({ access_token: "t", expires_in: 3600 });
    if (url.includes("accounts:lookup")) {
      const uid = JSON.parse(String(init?.body)).localId[0];
      return Response.json({ users: [{ localId: uid, validSince: "1", disabled: false }] });
    }
    if (url.endsWith(":commit")) {
      const writes = JSON.parse(String(init?.body)).writes;
      expect(writes[0]).toEqual({ verify: root + orderPath, currentDocument: { updateTime } });
      const last = writes.at(-1);
      expect(last.update.name).toBe(root + redemptionPath);
      expect(last.currentDocument).toEqual({ updateTime });
      Object.assign(source, last.update.fields);
      commits.push(writes);
      return Response.json({ writeResults: [] });
    }
    const path = url.split("/documents/")[1];
    return docs[path]
      ? Response.json({ name: root + path, fields: docs[path], updateTime })
      : new Response(null, { status: 404 });
  });
  const redeem = (uid: string, action: string, reference?: string) => worker.fetch(
    new Request("https://worker.test/v1/referrals/redemption", {
      method: "POST",
      headers: { Authorization: `Bearer ${uid}`, "Content-Type": "application/json" },
      body: JSON.stringify({ orderId: "points-order", action, reference }),
    }), env,
  );
  if (status === "cancelled") {
    expect((await redeem("stranger", "refund")).status).toBe(403);
    expect((await redeem("customer", "refund")).status).toBe(200);
    expect((await redeem("customer", "refund")).status).toBe(200);
    expect(commits).toHaveLength(1);
    expect(commits[0][1]).toMatchObject({
      transform: { document: root + "referral_balances/customer",
        fieldTransforms: [{ fieldPath: "points", increment: int(20) }] },
    });
  } else {
    expect((await redeem("customer", "refund")).status).toBe(409);
    expect((await redeem("customer", "claim")).status).toBe(403);
    expect((await redeem("admin", "paid", "transfer-1")).status).toBe(409);
    expect(await (await redeem("admin", "claim")).json()).toMatchObject({
      storeId: "store", discountMinor: 500, status: "processing",
    });
    expect((await redeem("other-admin", "claim")).status).toBe(409);
    expect((await redeem("admin", "paid", "transfer-1")).status).toBe(200);
    expect((await redeem("admin", "paid", "transfer-1")).status).toBe(200);
    expect(commits).toHaveLength(2);
  }
});
