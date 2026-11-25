import { describe, expect, it, vi } from "vitest";
import {
  commitVerifiedReferralGrant, ReferralCommitError, type FirestoreTransport,
} from "../src/referral_commit";

const request = {
  projectId: "wasally-test", transaction: "dHJhbnNhY3Rpb24=",
  grant: {
    grantId: "customer_invited", inviterUid: "inviter",
    invitedUid: "invited", sourceOrderId: "order-1",
    amount: 100, unit: "points" as const, policyVersion: 1,
  },
};

describe("referral transaction commit adapter", () => {
  it("sends a single transactional commit with create-only grant and increment", async () => {
    const transport = vi.fn(async () => ({
      ok: true, status: 200, text: async () => "{}",
    })) as FirestoreTransport;
    await expect(commitVerifiedReferralGrant(request, "token", transport))
      .resolves.toEqual({ committed: true });
    expect(transport).toHaveBeenCalledTimes(1);
    const [url, init] = vi.mocked(transport).mock.calls[0];
    expect(url).toContain("wasally-test/databases/(default)/documents:commit");
    expect(init.headers.Authorization).toBe("Bearer token");
    const payload = JSON.parse(init.body);
    expect(payload.transaction).toBe(request.transaction);
    expect(payload.writes).toHaveLength(2);
    expect(payload.writes[0].currentDocument).toEqual({ exists: false });
    expect(payload.writes[1].transform.fieldTransforms[0].increment.integerValue).toBe("100");
  });

  it("fails closed on Firestore errors without retrying", async () => {
    const transport = vi.fn(async () => ({
      ok: false, status: 409, text: async () => "conflict",
    })) as FirestoreTransport;
    await expect(commitVerifiedReferralGrant(request, "token", transport))
      .rejects.toBeInstanceOf(ReferralCommitError);
    expect(transport).toHaveBeenCalledTimes(1);
  });

  it("rejects missing transaction, token and invalid project before network", async () => {
    const transport = vi.fn() as unknown as FirestoreTransport;
    await expect(commitVerifiedReferralGrant({ ...request, transaction: "" }, "token", transport))
      .rejects.toThrow();
    await expect(commitVerifiedReferralGrant(request, "", transport)).rejects.toThrow();
    await expect(commitVerifiedReferralGrant({ ...request, projectId: "x/y" }, "token", transport))
      .rejects.toThrow();
    expect(transport).not.toHaveBeenCalled();
  });
});
