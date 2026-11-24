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
  REFERRAL_DEVICE_APP_CHECK_REQUIRED: "false",
  APP_CHECK_MODE: "off",
};

function call(uid: string, code = "ABC123", enabled = true) {
  return worker.fetch(new Request("https://worker.test/v1/referrals/registration", {
    method: "POST",
    headers: { Authorization: `Bearer ${uid}`, "Content-Type": "application/json" },
    body: JSON.stringify({ code, inviterUid: "untrusted", deviceId: "a1b2c3d4e5f60718" }),
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
    if ((url.includes("/documents/referral_deleted_identities/") ||
         url.includes("/documents/referral_device_bindings/")) &&
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
      if (name.startsWith(root + "referral_device_bindings/")) {
        expect(currentDocument).toEqual({ exists: false });
        expect(fields.googleOwnerDigest.stringValue).toMatch(/^[a-f0-9]{64}$/);
        expect(fields).not.toHaveProperty("rawAndroidId");
        expect(fields).not.toHaveProperty("uid");
        docs[name.slice(root.length)] = fields;
        return Response.json({});
      }
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
  const { saves, fetchMock } = setup("new-client");
  const firstClaim = await call("new-client", " abc123 ");
  expect(firstClaim.status,
    JSON.stringify(await firstClaim.json()) +
    " requests=" + fetchMock.mock.calls.map(([url, init]) =>
      String(url).split("/").slice(-2).join("/") + ":" + (init?.method ?? "GET")
    ).join(",")
  ).toBe(200);
  expect((await call("new-client")).status).toBe(200);
  expect((await call("new-client", "OTHER1")).status).toBe(409);
  expect(saves).toHaveLength(1);
});

it("reserves a shared phone for the first Google identity, blocks a second Google account", async () => {
  const firstUid = "first-google-on-phone";
  const secondUid = "second-google-on-phone";
  const { docs, fetchMock, saves } = setup(firstUid);
  const base = fetchMock.getMockImplementation()!;
  const deviceId = "a1b2c3d4e5f60718";
  const markerRequests: string[] = [];
  fetchMock.mockImplementation(async (input, init) => {
    const url = String(input);
    const body = typeof init?.body === "string" && init.body.startsWith("{")
      ? JSON.parse(init.body) : {};
    if (url.endsWith(":lookup") && body.localId?.[0] === secondUid) {
      const now = Date.now();
      return Response.json({ users: [{
        localId: secondUid, createdAt: String(now), lastLoginAt: String(now),
        validSince: "1",
        providerUserInfo: [{ providerId: "google.com", rawId: "second-google-subject-1234" }],
      }] });
    }
    if (url.includes("referral_device_bindings/")) markerRequests.push(url);
    return base(input, init);
  });
  const bind = (uid: string) => worker.fetch(new Request(
    "https://worker.test/v1/referrals/device-binding", {
      method: "POST",
      headers: { Authorization: `Bearer ${uid}`, "Content-Type": "application/json" },
      body: JSON.stringify({ deviceId }),
    }), env as never);
  const first = await bind(firstUid);
  expect(first.status,
    JSON.stringify(await first.clone().json()) +
    " requests=" + fetchMock.mock.calls.map(([url, init]) =>
      String(url).split("/").slice(-2).join("/") + ":" + (init?.method ?? "GET")
    ).join(",")
  ).toBe(200);
  expect((await first.json() as { eligible: boolean }).eligible).toBe(true);
  const again = await bind(firstUid);
  expect((await again.json() as { eligible: boolean }).eligible).toBe(true);
  expect(Object.keys(docs).filter(k => k.startsWith("referral_device_bindings/"))).toHaveLength(1);
  const second = await bind(secondUid);
  expect(second.status).toBe(200);
  expect((await second.json() as { eligible: boolean }).eligible).toBe(false);
  const claim = await call(secondUid);
  expect(claim.status).toBe(403);
  expect((await claim.json() as { error?: string }).error).toContain("نفس الموبايل");
  expect(saves).toHaveLength(0);
  expect(markerRequests.length).toBeGreaterThan(0);
});

it("rejects missing or fake Android device identifiers for invitation claims", async () => {
  setup("device-missing");
  const req = (deviceId?: string) => worker.fetch(new Request(
    "https://worker.test/v1/referrals/registration", {
      method: "POST",
      headers: { Authorization: "Bearer device-missing", "Content-Type": "application/json" },
      body: JSON.stringify({ code: "ABC123", ...(deviceId == null ? {} : { deviceId }) }),
    }), env as never);
  expect((await req()).status).toBe(403);
  expect((await req("0000000000000000")).status).toBe(403);
  expect((await req("bad-device")).status).toBe(403);
});

it("requires App Check for referral-device binding when production switch is enabled", async () => {
  const { fetchMock } = setup("appcheck-required");
  const result = await worker.fetch(new Request(
    "https://worker.test/v1/referrals/device-binding", {
      method: "POST",
      headers: { Authorization: "Bearer appcheck-required", "Content-Type": "application/json" },
      body: JSON.stringify({ deviceId: "a1b2c3d4e5f60718" }),
    }), { ...env, REFERRAL_DEVICE_APP_CHECK_REQUIRED: "true", FIREBASE_PROJECT_NUMBER: "244081237486" } as never);
  expect(result.status).toBe(401);
  expect(fetchMock).not.toHaveBeenCalled();
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
  expect(((await result.json()) as { error?: string }).error).toContain("حذف الحساب");
  expect(fetchMock.mock.calls.some(([url]) => String(url).endsWith(":beginTransaction"))).toBe(false);
  expect(saves).toHaveLength(0);
});

it("does not block a brand-new Google identity with no deletion marker", async () => {
  const { saves } = setup("different-firebase-user");
  expect((await call("different-firebase-user")).status).toBe(200);
  expect(saves).toHaveLength(1);
});

it("delete then rejoin same Google account: persistent HMAC marker prevents referral reuse", async () => {
  const oldUid = "deleted-rejoin-old";
  const newUid = "deleted-rejoin-new";
  const originalSubject = "google-subject-" + oldUid;
  const { fetchMock, docs } = setup(oldUid);
  const base = fetchMock.getMockImplementation()!;
  const events: string[] = [];
  const now = Date.now();
  fetchMock.mockImplementation(async (input, init) => {
    const url = String(input);
    const method = init?.method ?? "GET";
    const body = typeof init?.body === "string" && init.body.startsWith("{")
      ? JSON.parse(init.body) : {};
    if (url.endsWith("accounts:lookup") && body.localId?.[0] === newUid) {
      return Response.json({ users: [{
        localId: newUid,
        createdAt: String(now), lastLoginAt: String(now),
        validSince: "1",
        providerUserInfo: [{ providerId: "google.com", rawId: originalSubject }],
      }] });
    }
    if (url.endsWith("/accounts:delete")) {
      events.push("auth_deleted");
      expect(body.localId).toBe(oldUid);
      return Response.json({});
    }
    if (url.endsWith(":runQuery")) return Response.json([]);
    if (url.endsWith("/storeOwners/" + oldUid) && method === "GET") {
      return new Response("", { status: 404 });
    }
    if (url.endsWith(":commit")) {
      for (const write of (body.writes ?? [])) {
        if (write.update?.name?.includes("/referral_deleted_identities/")) {
          events.push("marker_saved");
          docs[write.update.name.slice(root.length)] = write.update.fields;
          expect(write.update.fields).not.toHaveProperty("email");
          expect(write.update.fields).not.toHaveProperty("uid");
          expect(write.update.fields).not.toHaveProperty("googleSubject");
        }
      }
      return Response.json({});
    }
    return base(input, init);
  });

  const deleted = await worker.fetch(new Request(
    "https://worker.test/v1/account/delete", {
      method: "POST", headers: { Authorization: `Bearer ${oldUid}` },
    }), env as never);
  expect(deleted.status).toBe(200);
  expect(events).toContain("marker_saved");
  expect(events.indexOf("marker_saved")).toBeLessThan(events.indexOf("auth_deleted"));
  expect(Object.keys(docs).some(key => key.startsWith("referral_deleted_identities/")))
    .toBe(true);

  const rejoined = await call(newUid);
  expect(rejoined.status).toBe(403);
  expect(((await rejoined.json()) as { error?: string }).error).toContain("حذف الحساب");
});

it("deletion never removes an account when saving a configured marker fails", async () => {
  const uid = "marker-write-failure-account";
  const { fetchMock } = setup(uid);
  const base = fetchMock.getMockImplementation()!;
  let authDeleted = false;
  fetchMock.mockImplementation(async (input, init) => {
    const url = String(input);
    if (url.endsWith(":commit")) return new Response("unavailable", { status: 503 });
    if (url.endsWith("/accounts:delete")) {
      authDeleted = true;
      return Response.json({});
    }
    return base(input, init);
  });
  const response = await worker.fetch(new Request(
    "https://worker.test/v1/account/delete", {
      method: "POST", headers: { Authorization: `Bearer ${uid}` },
    }), env as never);
  expect(response.status).toBeGreaterThanOrEqual(500);
  expect(authDeleted).toBe(false);
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
