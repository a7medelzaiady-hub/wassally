import { describe, expect, it, vi } from "vitest";
import { settleStoreReferral } from "../src/referral_store_settlement";
import type { FirestoreTransport } from "../src/referral_commit";

describe("store referral settlement coordinator", () => {
  it("rejects invalid store IDs before starting a transaction", async () => {
    const transport = vi.fn() as unknown as FirestoreTransport;
    await expect(settleStoreReferral("demo", "token", {
      invitedStoreId: "../other", firstOrderId: "order1",
    }, transport)).rejects.toThrow("invalid invited uid");
    expect(transport).not.toHaveBeenCalled();
  });
  it("does not write rewards when trusted attribution is missing", async () => {
    const root = "projects/demo/databases/(default)/documents";
    const transport = vi.fn(async (url: string, init: { body: string }) => {
      if (url.endsWith(":beginTransaction")) return new Response(
        JSON.stringify({ transaction: "YWJj" }), { status: 200 },
      );
      if (url.endsWith(":batchGet")) {
        const path = JSON.parse(init.body).documents[0] as string;
        return new Response(JSON.stringify({ missing: path }), { status: 200 });
      }
      throw new Error("unexpected commit");
    }) as unknown as FirestoreTransport;
    await expect(settleStoreReferral("demo", "token", {
      invitedStoreId: "store1", firstOrderId: "order1",
    }, transport)).resolves.toBe("ineligible");
    expect(transport.mock.calls.some(([url]: [string]) => url.endsWith(":commit"))).toBe(false);
    expect(root).toContain("projects/demo");
  });
  it("returns already_granted for a previously committed store reward", async () => {
    const root = "projects/demo/databases/(default)/documents";
    const transport = vi.fn(async (url: string) => {
      if (url.endsWith(":beginTransaction")) return new Response(
        JSON.stringify({ transaction: "YWJj" }), { status: 200 },
      );
      if (url.endsWith(":batchGet")) return new Response(JSON.stringify({
        found: { name: `${root}/referral_grants/store_owner_store1`,
          fields: { status: { stringValue: "granted" } } },
      }), { status: 200 });
      throw new Error("unexpected write");
    }) as unknown as FirestoreTransport;
    await expect(settleStoreReferral("demo", "token", {
      invitedStoreId: "store1", firstOrderId: "order1",
    }, transport)).resolves.toBe("already_granted");
    expect(transport).toHaveBeenCalledTimes(2);
  });
});
