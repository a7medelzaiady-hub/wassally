import { describe, expect, it, vi } from "vitest";
import { commitVerifiedAttribution } from "../src/referral_attribution_commit";
import type { FirestoreTransport } from "../src/referral_commit";

const claim = {
  invitedUid: "new-user", inviterUid: "owner", code: "ABC12345",
  channel: "customer" as const, claimedAtMs: 1000000,
};
const transaction = "dHJhbnNhY3Rpb24=";

describe("first-registration attribution commit", () => {
  it("commits an immutable attribution in the provided transaction", async () => {
    const transport = vi.fn(async () => ({ ok: true, status: 200, text: async () => "{}" }));
    await commitVerifiedAttribution("test-project", transaction, claim, "token", transport);
    const [url, init] = transport.mock.calls[0] as unknown as Parameters<FirestoreTransport>;
    expect(url).toContain("test-project/databases/(default)/documents:commit");
    const body = JSON.parse(init.body);
    expect(body.transaction).toBe(transaction);
    expect(body.writes).toHaveLength(1);
    expect(body.writes[0].currentDocument).toEqual({ exists: false });
    expect(body.writes[0].update.name).toContain("/referral_attributions/new-user");
  });

  it("uses store identity for immutable store claims", async () => {
    const transport = vi.fn(async () => ({ ok: true, status: 200, text: async () => "{}" }));
    await commitVerifiedAttribution("test-project", transaction,
      { ...claim, channel: "store_owner" }, "token", transport, "store-1");
    const body = JSON.parse(transport.mock.calls[0][1].body);
    expect(body.writes[0].update.name).toContain("/referral_store_attributions/store-1");
  });

  it("does not retry failed writes", async () => {
    const transport = vi.fn(async () => ({ ok: false, status: 409, text: async () => "" }));
    await expect(commitVerifiedAttribution("test-project", transaction, claim, "token", transport))
      .rejects.toThrow("409");
    expect(transport).toHaveBeenCalledTimes(1);
  });

  it("rejects missing credentials or transaction before network", async () => {
    const transport = vi.fn() as unknown as FirestoreTransport;
    await expect(commitVerifiedAttribution("test-project", "", claim, "token", transport))
      .rejects.toThrow();
    await expect(commitVerifiedAttribution("test-project", transaction, claim, "", transport))
      .rejects.toThrow();
    expect(transport).not.toHaveBeenCalled();
  });
});
