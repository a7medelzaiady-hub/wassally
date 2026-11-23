import { describe, expect, it, vi } from "vitest";
import { awardVerifiedReferral } from "../src/referral_award";
import type { FirestoreTransport } from "../src/referral_commit";

const root = "projects/demo/databases/(default)/documents";
const grant = {
  grantId: "customer_invited", inviterUid: "inviter", invitedUid: "invited",
  sourceOrderId: "order1", amount: 10, unit: "points" as const, policyVersion: 1,
};

describe("referral award transaction coordinator", () => {
  it("reads grant and canonical order in one transaction before committing", async () => {
    const requests: Array<{ url: string; body: Record<string, unknown> }> = [];
    const transport = vi.fn<FirestoreTransport>(async (url, init) => {
      const body = JSON.parse(init.body) as Record<string, unknown>;
      requests.push({ url, body });
      const result = url.endsWith(":beginTransaction")
        ? { transaction: "tx==" }
        : url.endsWith(":batchGet")
          ? (body.documents as string[])[0]!.endsWith("/referral_grants/customer_invited")
            ? { missing: `${root}/referral_grants/customer_invited` }
            : { found: { name: `${root}/orders/order1`, fields: { status: { stringValue: "delivered" } } } }
          : {};
      return { ok: true, status: 200, text: async () => JSON.stringify(result) };
    });
    const verifier = vi.fn(async (read: (collection: string, id: string) =>
      Promise<Record<string, unknown> | null>) => {
      const order = await read("orders", "order1");
      return order?.status && (order.status as { stringValue: string }).stringValue === "delivered"
        ? grant : null;
    });
    await expect(awardVerifiedReferral("demo", "token", grant.grantId, verifier, transport))
      .resolves.toBe("granted");
    expect(verifier).toHaveBeenCalledOnce();
    expect(requests.map((x) => x.url.split(":").pop())).toEqual([
      "beginTransaction", "batchGet", "batchGet", "commit",
    ]);
    expect(requests[3]!.body.transaction).toBe("tx==");
  });

  it("never awards an already existing grant", async () => {
    const transport = vi.fn<FirestoreTransport>(async (url) => ({
      ok: true, status: 200,
      text: async () => JSON.stringify(url.endsWith(":beginTransaction")
        ? { transaction: "tx==" }
        : { found: { name: `${root}/referral_grants/customer_invited`, fields: {} } }),
    }));
    const verify = vi.fn(async () => grant);
    await expect(awardVerifiedReferral("demo", "token", grant.grantId, verify, transport))
      .resolves.toBe("already_granted");
    expect(verify).not.toHaveBeenCalled();
    expect(transport).toHaveBeenCalledTimes(3);
  });

  it("does not retry a rejected commit or grant twice on a transaction conflict", async () => {
    let commitCalls = 0;
    const transport = vi.fn<FirestoreTransport>(async (url) => {
      if (url.endsWith(":commit")) {
        commitCalls++;
        return { ok: false, status: 409, text: async () => "conflict" };
      }
      const result = url.endsWith(":beginTransaction")
        ? { transaction: "tx==" }
        : { missing: `${root}/referral_grants/customer_invited` };
      return { ok: true, status: 200, text: async () => JSON.stringify(result) };
    });
    await expect(awardVerifiedReferral("demo", "token", grant.grantId,
      async (read) => { await read("referral_grants", "customer_invited"); return grant; }, transport)).rejects.toThrow("referral commit rejected");
    expect(commitCalls).toBe(1);
  });

  it("does not commit when canonical eligibility verification throws", async () => {
    const transport = vi.fn<FirestoreTransport>(async (url) => ({
      ok: true, status: 200,
      text: async () => JSON.stringify(url.endsWith(":beginTransaction")
        ? { transaction: "tx==" }
        : { missing: `${root}/referral_grants/customer_invited` }),
    }));
    await expect(awardVerifiedReferral("demo", "token", grant.grantId,
      async () => { throw new Error("invalid canonical order"); }, transport))
      .rejects.toThrow("invalid canonical order");
    expect(transport.mock.calls.some(([url]) => url.endsWith(":commit"))).toBe(false);
  });

  it("rejects an award when the verifier performs no canonical reads", async () => {
    const transport = vi.fn<FirestoreTransport>(async (url) => ({
      ok: true, status: 200,
      text: async () => JSON.stringify(url.endsWith(":beginTransaction")
        ? { transaction: "tx==" }
        : { missing: `${root}/referral_grants/customer_invited` }),
    }));
    await expect(awardVerifiedReferral("demo", "token", grant.grantId,
      async () => grant, transport)).rejects.toThrow("canonical Firestore reads");
    expect(transport.mock.calls.some(([url]) => url.endsWith(":commit"))).toBe(false);
  });

  it("fails closed when eligibility is absent or mismatched", async () => {
    const transport = vi.fn<FirestoreTransport>(async (url) => ({
      ok: true, status: 200,
      text: async () => JSON.stringify(url.endsWith(":beginTransaction")
        ? { transaction: "tx==" }
        : { missing: `${root}/referral_grants/customer_invited` }),
    }));
    await expect(awardVerifiedReferral("demo", "token", grant.grantId,
      async () => null, transport)).resolves.toBe("ineligible");
    await expect(awardVerifiedReferral("demo", "token", grant.grantId,
      async (read) => { await read("referral_grants", "customer_invited"); return { ...grant, grantId: "wrong" }; }, transport)).rejects.toThrow("mismatch");
    expect(transport.mock.calls.every(([url]) => !url.endsWith(":commit"))).toBe(true);
  });
});
