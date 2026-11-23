import { afterEach, describe, expect, it, vi } from "vitest";

vi.mock("jose", () => ({
  createRemoteJWKSet: () => () => ({}),
  // الـtoken في الاختبار = uid.
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

import worker from "../src/index";

const env = {
  FIREBASE_PROJECT_ID: "wasally-test",
  FIREBASE_SERVICE_ACCOUNT_EMAIL: "test@wasally-test.iam.gserviceaccount.com",
  FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY: "mock-key",
  APP_CHECK_MODE: "off",
} as never;

function enc(v: unknown): unknown {
  if (v === null || v === undefined) return { nullValue: null };
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (typeof v === "string") return { stringValue: v };
  if (typeof v === "boolean") return { booleanValue: v };
  if (typeof v === "number") return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(enc) } };
  return { mapValue: { fields: fields(v as Record<string, unknown>) } };
}
const fields = (m: Record<string, unknown>): Record<string, unknown> =>
  Object.fromEntries(Object.entries(m).map(([k, v]) => [k, enc(v)]));

const prefix = "projects/wasally-test/databases/(default)/documents/";
const orderId = "regular-order";

function simulate(order: Record<string, unknown> = {}, history?: Record<string, unknown>) {
  const docs: Record<string, Record<string, unknown> | undefined> = {
    [`orders/${orderId}`]: {
      userId: "customer", storeId: "store", courierId: "courier",
      createdAt: new Date(), status: "new", notes: "private note",
      ...order,
    },
    [`orders/${orderId}/statusHistory/preparing`]: history,
    "couriers/courier": { active: true },
    "storeOwners/owner": { active: true, storeId: "store" },
    "users/customer": { fcmTokens: ["customer-device"] },
    "users/owner": { fcmTokens: ["owner-device"] },
    "users/courier": { fcmTokens: ["courier-device"] },
  };
  const claims = new Set<string>();
  const messages: unknown[] = [];
  const doc = (path: string, value: Record<string, unknown>) => ({
    name: prefix + path,
    fields: fields(value),
  });
  vi.spyOn(globalThis, "fetch").mockImplementation(async (resource, init) => {
    const url = String(resource);
    if (url.includes("oauth2.googleapis.com/token")) {
      return Response.json({ access_token: "t", expires_in: 3600 });
    }
    if (url.includes("accounts:lookup")) {
      const uid = JSON.parse(String(init?.body)).localId[0];
      return Response.json({ users: [{ localId: uid, validSince: "1", disabled: false }] });
    }
    if (url.includes("fcm.googleapis.com")) {
      messages.push(JSON.parse(String(init?.body)).message);
      return Response.json({ name: "sent" });
    }
    if (url.endsWith(":runQuery")) {
      return Response.json([{ document: doc("storeOwners/owner", { active: true }) }]);
    }
    if (url.endsWith(":commit")) {
      const [{ update: { name }, currentDocument }] = JSON.parse(String(init?.body)).writes;
      expect(currentDocument).toEqual({ exists: false });
      if (claims.has(name)) {
        return Response.json({ error: { status: "FAILED_PRECONDITION" } }, { status: 400 });
      }
      claims.add(name);
      return Response.json({ writeResults: [] });
    }
    const path = url.split("/documents/")[1];
    return docs[path]
      ? Response.json(doc(path, docs[path]))
      : new Response(null, { status: 404 });
  });
  return { claims, messages };
}

const call = (uid: string, event: string, status?: string) =>
  worker.fetch(new Request("https://worker.test/v1/order-events", {
    method: "POST",
    headers: { Authorization: `Bearer ${uid}`, "Content-Type": "application/json" },
    body: JSON.stringify({ orderId, event, status }),
  }), env);

afterEach(() => vi.restoreAllMocks());

describe("regular order pushes", () => {
  it("sends a new order only to the store owner and deduplicates concurrent calls", async () => {
    const { claims, messages } = simulate();
    const responses = await Promise.all([call("customer", "created"), call("customer", "created")]);
    expect(responses.map(({ status }) => status)).toEqual([200, 200]);
    expect(claims.size).toBe(1);
    expect(messages).toEqual([expect.objectContaining({
      token: "owner-device",
      data: { type: "store_order_update", orderId },
    })]);
    expect(JSON.stringify(messages)).not.toContain("private note");
  });

  it("authorizes a status push using the committed history actor", async () => {
    const { claims, messages } = simulate(
      { status: "preparing" },
      { actorUid: "owner", to: "preparing", at: new Date() },
    );
    expect((await call("stranger", "status", "preparing")).status).toBe(403);
    expect(claims.size).toBe(0);
    expect((await call("owner", "status", "preparing")).status).toBe(200);
    expect(messages).toEqual([expect.objectContaining({
      token: "customer-device",
      data: { type: "order_update", orderId },
    })]);
  });

  it("sends a ready event only on behalf of an active owner of the store", async () => {
    const { claims, messages } = simulate({
      status: "preparing", ready: true, readyAt: new Date(),
    });
    expect((await call("stranger", "ready")).status).toBe(403);
    expect(claims.size).toBe(0);
    expect((await call("owner", "ready")).status).toBe(200);
    expect(messages).toEqual(expect.arrayContaining([
      expect.objectContaining({ token: "customer-device", data: { type: "order_update", orderId } }),
      expect.objectContaining({ token: "courier-device", data: { type: "courier_order_update", orderId } }),
    ]));
    expect(messages).toHaveLength(2);
  });

  it("ignores a status that has already changed", async () => {
    const { claims, messages } = simulate({ status: "delivered" });
    expect((await call("owner", "status", "preparing")).status).toBe(200);
    expect(claims.size).toBe(0);
    expect(messages).toEqual([]);
  });
  it("rejects unauthenticated status events without creating a push claim", async () => {
    const { claims, messages } = simulate(
      { status: "preparing" },
      { actorUid: "owner", to: "preparing", at: new Date() },
    );
    const res = await worker.fetch(new Request("https://worker.test/v1/order-events", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ orderId, event: "status", status: "preparing" }),
    }), env);
    expect(res.status).toBe(401);
    expect(claims.size).toBe(0);
    expect(messages).toEqual([]);
  });

  it("never includes private contact details in status push payloads", async () => {
    const { messages } = simulate(
      { status: "preparing", phone: "PRIVATE_PHONE_123", address: "PRIVATE_ADDRESS_456" },
      { actorUid: "owner", to: "preparing", at: new Date() },
    );
    expect((await call("owner", "status", "preparing")).status).toBe(200);
    const payload = JSON.stringify(messages);
    expect(payload).not.toContain("PRIVATE_PHONE_123");
    expect(payload).not.toContain("PRIVATE_ADDRESS_456");
  });

});
