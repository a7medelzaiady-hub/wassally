/**
 * Immutable server-owned first successful store order index.
 * This is only a write plan: caller must establish genuine first successful
 * order using trusted history and commit with the order transition.
 * Never append blindly to each delivery (would block later deliveries).
 */
export function buildFirstStoreOrderWrite(
  root: string,
  evidence: { invitedStoreId: string; orderId: string; completedAtMs: number },
) {
  const validId = (id: string) => /^[A-Za-z0-9_-]{1,128}$/.test(id);
  if (!/^projects\/[A-Za-z0-9_-]+\/databases\/\(default\)\/documents$/.test(root) ||
      !validId(evidence.invitedStoreId) || !validId(evidence.orderId) ||
      !Number.isSafeInteger(evidence.completedAtMs) || evidence.completedAtMs <= 0) {
    throw new Error("invalid first store order evidence");
  }
  return {
    update: {
      name: `${root}/referral_store_first_orders/${evidence.invitedStoreId}`,
      fields: {
        invitedStoreId: { stringValue: evidence.invitedStoreId },
        firstCompletedOrderId: { stringValue: evidence.orderId },
        completedAtMs: { integerValue: String(evidence.completedAtMs) },
      },
    },
    currentDocument: { exists: false },
  };
}
