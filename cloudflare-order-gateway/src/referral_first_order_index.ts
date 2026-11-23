/**
 * Server-owned first successful order index. Must be committed atomically with
 * the trusted order completion transition. Never called by the client.
 * exists:false means the first completed order wins under concurrency.
 */
export function buildFirstCompletedOrderWrite(
  root: string,
  evidence: { invitedUid: string; orderId: string; completedAtMs: number },
) {
  const validId = (v: string) => /^[A-Za-z0-9_-]{1,128}$/.test(v);
  if (!/^projects\/[A-Za-z0-9_-]+\/databases\/\(default\)\/documents$/.test(root)) {
    throw new Error("invalid Firestore root");
  }
  if (!validId(evidence.invitedUid) || !validId(evidence.orderId)) {
    throw new Error("invalid first order identity");
  }
  if (!Number.isSafeInteger(evidence.completedAtMs) || evidence.completedAtMs <= 0) {
    throw new Error("invalid completion timestamp");
  }
  return {
    update: {
      name: `${root}/referral_first_orders/${evidence.invitedUid}`,
      fields: {
        invitedUid: { stringValue: evidence.invitedUid },
        firstCompletedOrderId: { stringValue: evidence.orderId },
        completedAtMs: { integerValue: String(evidence.completedAtMs) },
      },
    },
    currentDocument: { exists: false },
  };
}
