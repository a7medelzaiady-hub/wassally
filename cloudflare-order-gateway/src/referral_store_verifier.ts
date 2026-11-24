import { decodeFirestoreReferralFields } from "./referral_firestore_values";
import { decideReferralReward } from "./referrals";
import { parseReferralSettings } from "./referral_settings";
import type { VerifiedReferralGrant } from "./referral_grants";

type Read = (collection: string, id: string) => Promise<Record<string, unknown> | null>;
const validId = (id: string) => /^[A-Za-z0-9_-]{1,128}$/.test(id);

/**
 * Store-to-store reward verifier, strictly based on canonical transactional
 * documents. Never trust store approval, activation or reward amount from UI.
 * Integration requires a server-maintained first successful store order index.
 */
export async function verifyStoreReferral(
  read: Read,
  evidence: { invitedStoreId: string; firstOrderId: string },
): Promise<VerifiedReferralGrant | null> {
  if (!validId(evidence.invitedStoreId) || !validId(evidence.firstOrderId)) {
    throw new Error("invalid store referral identity");
  }
  const [attributionRaw, storeRaw, orderRaw, indexRaw, settingsRaw, originRaw] = await Promise.all([
    read("referral_store_attributions", evidence.invitedStoreId),
    read("stores", evidence.invitedStoreId),
    read("orders", evidence.firstOrderId),
    read("referral_store_first_orders", evidence.invitedStoreId),
    read("app_info", "referral_config"),
    read("referral_store_origins", evidence.invitedStoreId),
  ]);
  if (!attributionRaw || !storeRaw || !orderRaw || !indexRaw || !settingsRaw || !originRaw) return null;
  const attribution = decodeFirestoreReferralFields(attributionRaw);
  const store = decodeFirestoreReferralFields(storeRaw);
  const order = decodeFirestoreReferralFields(orderRaw);
  const origin = decodeFirestoreReferralFields(originRaw);
  const index = decodeFirestoreReferralFields(indexRaw);
  const settings = parseReferralSettings(decodeFirestoreReferralFields(settingsRaw));
  if (attribution.invitedStoreId !== evidence.invitedStoreId ||
      attribution.channel !== "store_owner" ||
      typeof attribution.inviterUid !== "string" ||
      typeof attribution.invitedUid !== "string" ||
      typeof attribution.claimedAtMs !== "number" ||
      !validId(attribution.inviterUid) || !validId(attribution.invitedUid) ||
      origin.uid !== attribution.invitedUid || origin.approvalAt !== store.approvedAt ||
      store.active !== true || store.approved !== true ||
      !Number.isSafeInteger(store.approvedAt) ||
      !Number.isSafeInteger(store.firstActivatedAt) ||
      index.invitedStoreId !== evidence.invitedStoreId ||
      index.firstCompletedOrderId !== evidence.firstOrderId ||
      !Number.isSafeInteger(index.completedAtMs) ||
      order.storeId !== evidence.invitedStoreId ||
      order.status !== "delivered" ||
      !Number.isSafeInteger(order.deliveredAt) ||
      order.deliveredAt !== index.completedAtMs) return null;

  // An attribution naming an owner is not proof that the owner owns this store.
  // Verify the canonical store-owner assignment in the same transaction.
  const [invitedOwnerRaw, inviterOwnerRaw] = await Promise.all([
    read("storeOwners", attribution.invitedUid),
    read("storeOwners", attribution.inviterUid),
  ]);
  if (!invitedOwnerRaw || !inviterOwnerRaw) return null;
  // firestore.rules allows storeOwners.active to be omitted (default true).
  // Match that canonical schema; explicitly false always disqualifies.
  const invitedOwner = decodeFirestoreReferralFields(invitedOwnerRaw);
  const inviterOwner = decodeFirestoreReferralFields(inviterOwnerRaw);
  if (invitedOwner.storeId !== evidence.invitedStoreId || invitedOwner.active === false ||
      inviterOwner.active === false || typeof inviterOwner.storeId !== "string" ||
      !validId(inviterOwner.storeId) ||
      inviterOwner.storeId === evidence.invitedStoreId) return null;

  // The inviter must still own an approved, active store. A stale owner mapping
  // alone cannot authorize a store-to-store payout.
  const inviterStoreRaw = await read("stores", inviterOwner.storeId as string);
  if (!inviterStoreRaw) return null;
  const inviterStore = decodeFirestoreReferralFields(inviterStoreRaw);
  if (inviterStore.active !== true || inviterStore.approved !== true) return null;

  const balanceRaw = await read("referral_balances", attribution.inviterUid);
  let previousAwards = 0;
  if (balanceRaw) {
    const balance = decodeFirestoreReferralFields(balanceRaw);
    const counter = balance.storeOwnerAwardsCount ?? 0;
    if (typeof counter !== "number" || !Number.isSafeInteger(counter) || counter < 0) return null;
    previousAwards = counter;
  }
  const decision = decideReferralReward(settings.policies.store_owner, {
    inviterUid: attribution.inviterUid,
    invitedUid: attribution.invitedUid,
    invitedStoreId: evidence.invitedStoreId,
    channel: "store_owner",
    attributedAt: attribution.claimedAtMs as number,
    firstCompletedOrderAt: order.deliveredAt as number,
    storeApprovedAt: store.approvedAt as number,
    storeActivatedAt: store.firstActivatedAt as number,
    previousAwards,
  });
  if (!decision.eligible) return null;
  return {
    grantId: decision.grantId, inviterUid: attribution.inviterUid,
    invitedUid: attribution.invitedUid, sourceOrderId: evidence.firstOrderId,
    amount: decision.amount, unit: decision.unit, policyVersion: settings.version,
  };
}
