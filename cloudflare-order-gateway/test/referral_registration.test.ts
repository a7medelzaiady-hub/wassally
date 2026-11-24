import { afterEach, expect, it, vi } from "vitest";

const auth = vi.hoisted(() => ({ time: 0 }));
vi.mock("jose", () => ({
  createRemoteJWKSet: () => () => ({}),
  jwtVerify: async (uid: string) => ({
    payload: { sub: uid, auth_time: auth.time, firebase: { sign_in_provider: "google.com" } },
  }),
  importPKCS8: async () => ({}),
  SignJWT: class {
    setProtectedHeader() { return this; }
    setIssuer() { return this; }
    setAudience() { return this; }
    setIssuedAt() { return this; }
    setExpirationTime() { return this; }
    async sign() { return "mock-jwt"; }
  },
}));

import worker from "../src/index";
import { referralIdentityDocumentId } from "../src/referral_identity";

const root = "projects/referral-test/databases/(default)/documents/";
const env = {
  FIREBASE_PROJECT_ID: "referral-test",
  FIREBASE_SERVICE_ACCOUNT_EMAIL: "test@example.com",
  FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY: "mock-key",
  REFERRAL_REGISTRATION_ENABLED: "true",
  REFERRAL_IDENTITY_HMAC_KEY: "fake-secret-for-automated-tests-only-0123456789",
  APP_CHECK_MODE: "off",
};

function call(uid: string, code = "ABC123", enabled = true) {
  return worker.fetch(new Request("https://worker.test/v1/referrals/registration", {
    method: "POST",
    headers: { Authorization: `Bearer ${uid}`, "Content-Type": "application/json" },
    body: JSON.stringify({ code, inviterUid: "untrusted" }),
  }), { ...env, REFERRAL_REGISTRATION_ENABLED: String(enabled) } as never);
}

function setup(uid: string, channel = "customer", creationOffset = 0) {
  const now = Date.now();
  const created = now - creationOffset;
  auth.time = Math.floor(now / 1000);
  const str = (stringValue: string) => ({ stringValue });
  const int = (n: number) => ({ integerValue: String(n) });
  const yes = { booleanValue: true };
  const policy = (name: string, unit: string) => ({ mapValue: { fields: {
    channel: str(name), unit: str(unit), amount: int(10), enabled: yes,
  } } });
  const docs: Record<string, Record<string, unknown>> = {
    "referral_codes/ABC123": {
      code: str("ABC123"), inviterUid: str("inviter"), channel: str(channel),
      active: yes, issuedByUid: str("admin"),
    },
    "app_info/referral_config": { version: int(1), policies: { mapValue: { fields: {
      customer: policy("customer", "points"), marketer: policy("marketer", "cash_minor"),
      store_owner: policy("store_owner", "commission_discount_minor"),
    } } } },
  };
  const saves: string[] = [];
  const fetchMock = vi.spyOn(globalThis, "fetch").mockImplementation(async (resource, init) => {
    const url = String(resource);
    const body = init?.body && String(init.body).startsWith("{") ? JSON.parse(String(init.body)) : {};
    if (url.includes("oauth2.googleapis.com/token")) {
      return Response.json({ access_token: "mock-token", expires_in: 3600 });
    }
    if (url.endsWith(":lookup")) {
      expect(body.localId).toEqual([uid]);
      return Response.json({ users: [{
        localId: uid, createdAt: String(created), lastLoginAt: String(created), validSince: "1",
        providerUserInfo: [{ providerId: "google.com", rawId: "google-subject-" + uid }],
      }] });
    }
    if (url.includes("/documents/referral_deleted_identities/") &&
        (!init?.method || init.method === "GET")) {
      const path = url.split("/documents/")[1];
      const fields = docs[path];
      return fields ? Response.json({ name: root + path, fields }) : new Response("", { status: 404 });
    }
    if (url.endsWith(":beginTransaction")) return Response.json({ transaction: "abc" });
    expect(body.transaction).toBe("abc");
    if (url.endsWith(":batchGet")) {
      const [name] = body.documents;
      const fields = docs[name.slice(root.length)];
      return Response.json(fields ? { found: { name, fields } } : { missing: name });
    }
    if (url.endsWith(":rollback")) return Response.json({});
    if (url.endsWith(":commit")) {
      const [{ update: { name, fields }, currentDocument }] = body.writes;
      expect(currentDocument).toEqual({ exists: false });
      expect(name).toBe(root + `referral_attributions/${uid}`);
      expect(fields.inviterUid).toEqual(str("inviter"));
      docs[name.slice(root.length)] = fields;
      saves.push(name);
      return Response.json({});
    }
    throw new Error(`Unexpected request ${url}`);
  });
  return { fetchMock, saves, docs };
}

afterEach(() => vi.restoreAllMocks());

it("binds the first registration once and accepts a retry of the same code", async () => {
  const { saves } = setup("new-client");
  expect((await call("new-client", " abc123 ")).status).toBe(200);
  expect((await call("new-client")).status).toBe(200);
  expect((await call("new-client", "OTHER1")).status).toBe(409);
  expect(saves).toHaveLength(1);
});

it("rejects a later login before opening a Firestore transaction", async () => {
  const { fetchMock } = setup("returning-client", "customer", 10_000);
  expect((await call("returning-client")).status).toBe(403);
  expect(fetchMock.mock.calls.some(([url]) => String(url).endsWith(":beginTransaction"))).toBe(false);
});

it("blocks an account recreated from a deleted Google identity even with a new Firebase UID", async () => {
  const { docs, saves, fetchMock } = setup("firebase-new-uid");
  const googleSubject = "google-subject-firebase-new-uid";
  const digest = await referralIdentityDocumentId(env.REFERRAL_IDENTITY_HMAC_KEY, googleSubject);
  docs[`referral_deleted_identities/${digest}`] = {
    reason: { stringValue: "deleted_account_referral_prevention" },
    expiresAt: { timestampValue: new Date(Date.now() + 86400000).toISOString() },
  };
  const result = await call("firebase-new-uid");
  expect(result.status).toBe(403);
  expect((await result.json()).error).toContain("حذف الحساب");
  expect(fetchMock.mock.calls.some(([url]) => String(url).endsWith(":beginTransaction"))).toBe(false);
  expect(saves).toHaveLength(0);
});

it("does not block a brand-new Google identity with no deletion marker", async () => {
  const { saves } = setup("different-firebase-user");
  expect((await call("different-firebase-user")).status).toBe(200);
  expect(saves).toHaveLength(1);
});

it("requires a marketer code issued by an administrator", async () => {
  const { docs, saves } = setup("marketer-client", "marketer");
  expect((await call("marketer-client")).status).toBe(409);
  docs["admins/admin"] = {};
  expect((await call("marketer-client")).status).toBe(200);
  expect(saves).toHaveLength(1);
});

it("keeps the disabled route away from Firebase", async () => {
  const { fetchMock } = setup("disabled-client");
  expect((await call("disabled-client", "ABC123", false)).status).toBe(404);
  expect(fetchMock).not.toHaveBeenCalled();
});

it("credits the inviter once from the earliest canonical delivered order", async () => {
  const uid = "first-delivery-client";
  const { docs, fetchMock, saves } = setup(uid);
  expect((await call(uid)).status).toBe(200);
  const order = {
    name: root + "orders/earliest",
    fields: {
      userId: { stringValue: uid },
      status: { stringValue: "delivered" },
      deliveredAt: { timestampValue: new Date(Date.now() + 1000).toISOString() },
    },
  };
  docs["orders/earliest"] = order.fields;
  const baseFetch = fetchMock.getMockImplementation()!;
  let queries = 0;
  let grants = 0;
  fetchMock.mockImplementation(async (url, init) => {
    const endpoint = String(url);
    if (endpoint.endsWith(":runQuery")) {
      const { transaction, structuredQuery } = JSON.parse(String(init?.body));
      expect(transaction).toBe("abc");
      expect(structuredQuery.limit).toBe(1);
      expect(structuredQuery.orderBy[0]).toEqual({
        field: { fieldPath: "deliveredAt" }, direction: "ASCENDING",
      });
      queries++;
      return Response.json(structuredQuery.from[0].collectionId === "orders" ? [{ document: order }] : []);
    }
    if (endpoint.endsWith(":commit")) {
      const { transaction, writes } = JSON.parse(String(init?.body));
      expect(transaction).toBe("abc");
      const [{ update, currentDocument }] = writes;
      const path = update.name.slice(root.length);
      expect(currentDocument).toEqual({ exists: false });
      if (path === `referral_grants/customer_${uid}`) {
        expect(update.fields.sourceOrderId).toEqual({ stringValue: "earliest" });
        expect(writes[1].transform.document).toBe(root + "referral_balances/inviter");
        expect(writes[1].transform.fieldTransforms).toContainEqual({
          fieldPath: "points", increment: { integerValue: "10" },
        });
        grants++;
      } else {
        expect(path).toBe(`referral_first_orders/${uid}`);
      }
      docs[path] = update.fields;
      return Response.json({});
    }
    return baseFetch(url, init);
  });
  const { settleCustomerDelivery } = await import("../src/referral_delivery");
  await settleCustomerDelivery("referral-test", "mock-token", uid, fetch);
  await settleCustomerDelivery("referral-test", "mock-token", uid, fetch);
  expect(queries).toBe(2);
  expect(grants).toBe(1);
  expect(saves).toHaveLength(1);
});

it("settles a new store invitation through approved origin, activation and first delivery", async () => {
  const uid = "new-store-owner";
  const { docs, fetchMock } = setup(uid, "store_owner");
  const str = (stringValue: string) => ({ stringValue });
  const yes = { booleanValue: true };
  const timestamp = (ms: number) => ({ timestampValue: new Date(ms).toISOString() });
  docs["storeOwners/inviter"] = { storeId: str("original") };
  docs["stores/original"] = { active: yes, approved: yes };
  expect((await call(uid)).status).toBe(200);

  const now = Date.now();
  docs["referral_store_origins/new-store"] = { uid: str(uid), approvalAt: timestamp(now + 1000) };
  docs["storeOwners/" + uid] = { storeId: str("new-store"), active: yes };
  docs["stores/new-store"] = {
    approvedAt: timestamp(now + 1000), firstActivatedAt: timestamp(now + 2000),
    active: yes, approved: yes,
  };
  const fields = {
    storeId: str("new-store"), status: str("delivered"), deliveredAt: timestamp(now + 3000),
  };
  docs["orders/store-order"] = fields;
  const baseFetch = fetchMock.getMockImplementation()!;
  let storesCredited = 0;
  fetchMock.mockImplementation(async (url, init) => {
    const endpoint = String(url);
    if (endpoint.endsWith(":runQuery")) {
      expect(JSON.parse(String(init?.body)).structuredQuery.where.compositeFilter.filters[0])
        .toMatchObject({ fieldFilter: { field: { fieldPath: "storeId" }, value: str("new-store") } });
      return Response.json([{ document: { name: root + "orders/store-order", fields } }]);
    }
    if (endpoint.endsWith(":commit")) {
      const { writes } = JSON.parse(String(init?.body));
      for (const { update } of writes) {
        if (update) docs[update.name.slice(root.length)] = update.fields;
      }
      const balance = writes.find((write: { transform?: unknown }) => write.transform);
      if (balance) {
        expect(balance.transform.document).toBe(root + "referral_balances/inviter");
        expect(balance.transform.fieldTransforms).toContainEqual({
          fieldPath: "commissionDiscountMinor", increment: { integerValue: "10" },
        });
        storesCredited++;
      }
      return Response.json({});
    }
    return baseFetch(url, init);
  });
  const { settleStoreDelivery } = await import("../src/referral_delivery");
  await settleStoreDelivery("referral-test", "mock-token", "new-store", fetch);
  await settleStoreDelivery("referral-test", "mock-token", "new-store", fetch);
  expect(storesCredited).toBe(1);
  expect(docs["referral_grants/store_owner_new-store"].sourceOrderId).toEqual(str("store-order"));
});
