import { describe, expect, it, vi } from "vitest";
import { settleFirstOrderReferral } from "../src/referral_settlement";
import type { FirestoreTransport } from "../src/referral_commit";

const root = "projects/demo/databases/(default)/documents";
const sv = (s: string) => ({ stringValue: s });
const iv = (n: number) => ({ integerValue: String(n) });
const policy = (channel: string, unit: string) => ({ mapValue: { fields: {
  channel: sv(channel), unit: sv(unit), enabled: { booleanValue: true }, amount: iv(10),
} } });
const docs: Record<string, Record<string, unknown>> = {
  "referral_attributions/invited": {
    invitedUid: sv("invited"), inviterUid: sv("inviter"), channel: sv("customer"), claimedAtMs: iv(100),
  },
  "orders/order1": { userId: sv("invited"), status: sv("delivered"), deliveredAt: { timestampValue: "1970-01-01T00:00:00.200Z" } },
  "referral_first_orders/invited": {
    invitedUid: sv("invited"), firstCompletedOrderId: sv("order1"), completedAtMs: iv(200),
  },
  "app_info/referral_config": {
    version: iv(1), policies: { mapValue: { fields: {
      customer: policy("customer", "points"), marketer: policy("marketer", "cash_minor"),
      store_owner: policy("store_owner", "cash_minor"),
    } } },
  },
};
describe("internal referral settlement", () => {
  it("verifies all canonical records and commits reward with the same transaction", async () => {
    const calls: string[] = [];
    const transport = vi.fn<FirestoreTransport>(async (url, init) => {
      calls.push(url);
      const body = JSON.parse(init.body) as { documents?: string[]; transaction?: string };
      let result: unknown = {};
      if (url.endsWith(":beginTransaction")) result = { transaction: "tx==" };
      if (url.endsWith(":batchGet")) {
        expect(body.transaction).toBe("tx==");
        const name = body.documents![0]!;
        const key = name.slice(root.length + 1);
        result = docs[key] ? { found: { name, fields: docs[key] } } : { missing: name };
      }
      if (url.endsWith(":commit")) expect(body.transaction).toBe("tx==");
      return { ok: true, status: 200, text: async () => JSON.stringify(result) };
    });
    await expect(settleFirstOrderReferral("demo", "oauth", "invited", "order1",
      "customer", transport)).resolves.toBe("granted");
    expect(calls.filter((x) => x.endsWith(":commit"))).toHaveLength(1);
    expect(calls.filter((x) => x.endsWith(":batchGet"))).toHaveLength(6);
  });

  it("does not award if first order proof is absent", async () => {
    const transport = vi.fn<FirestoreTransport>(async (url, init) => {
      const body = JSON.parse(init.body) as { documents?: string[] };
      const name = body.documents?.[0] ?? "";
      const key = name.slice(root.length + 1);
      const result = url.endsWith(":beginTransaction") ? { transaction: "tx==" }
        : docs[key] && key !== "referral_first_orders/invited"
          ? { found: { name, fields: docs[key] } } : { missing: name };
      return { ok: true, status: 200, text: async () => JSON.stringify(result) };
    });
    await expect(settleFirstOrderReferral("demo", "oauth", "invited", "order1",
      "customer", transport)).resolves.toBe("ineligible");
    expect(transport.mock.calls.some(([url]) => url.endsWith(":commit"))).toBe(false);
  });
});
