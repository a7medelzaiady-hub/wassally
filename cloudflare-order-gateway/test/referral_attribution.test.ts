import { describe, expect, it } from "vitest";
import {
  buildReferralAttributionWrite, buildStoreAttributionWrite,
} from "../src/referral_attribution";

const root = "projects/wasally-test/databases/(default)/documents";
const claim = {
  invitedUid: "new-user", inviterUid: "existing-user", code: " abcd12 ",
  channel: "customer" as const, claimedAtMs: 1700000000000,
};

describe("immutable referral attribution plans", () => {
  it("creates a single first-registration attribution with exists=false", () => {
    const write = buildReferralAttributionWrite(root, claim);
    expect(write.currentDocument).toEqual({ exists: false });
    expect(write.update.name).toBe(`${root}/referral_attributions/new-user`);
    expect(write.update.fields.code).toEqual({ stringValue: "ABCD12" });
  });

  it("keys store invitations by store ID", () => {
    const write = buildStoreAttributionWrite(root, "new-store", {
      ...claim, channel: "store_owner",
    });
    expect(write.update.name).toBe(`${root}/referral_store_attributions/new-store`);
    expect(write.currentDocument).toEqual({ exists: false });
  });

  it("rejects self-referral, unsafe IDs, invalid codes and invalid time", () => {
    expect(() => buildReferralAttributionWrite(root, {
      ...claim, inviterUid: claim.invitedUid,
    })).toThrow();
    expect(() => buildReferralAttributionWrite(root, {
      ...claim, invitedUid: "a/b",
    })).toThrow();
    expect(() => buildReferralAttributionWrite(root, {
      ...claim, code: "AB-12",
    })).toThrow();
    expect(() => buildReferralAttributionWrite(root, {
      ...claim, claimedAtMs: 0,
    })).toThrow();
    expect(() => buildStoreAttributionWrite(root, "bad/id", {
      ...claim, channel: "store_owner",
    })).toThrow();
    expect(() => buildStoreAttributionWrite(root, "store", claim)).toThrow();
  });
});
