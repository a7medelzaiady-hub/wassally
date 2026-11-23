import { decodeFirestoreReferralFields } from "./referral_firestore_values";
import { decideReferralReward, type ReferralChannel } from "./referrals";
import { parseReferralSettings } from "./referral_settings";
import type { VerifiedReferralGrant } from "./referral_grants";

type Read = (collection: string, id: string) => Promise<Record<string, unknown> | null>;
const validId = (v: string) => /^[A-Za-z0-9_-]{1,128}$/.test(v);

/**
 * Canonical customer/marketer award verifier for the isolated referral schema.
 * This is not wired into the public Worker router. A trusted handler must
 * establish the canonical FIRST successful order before invoking it.
 * Merely seeing an order with status delivered is NOT proof it was first.
 */
export async function verifyFirstOrderReferral(
  read: Read,
  evidence: {
    invitedUid: string;
    firstOrderId: string;
    /** Verified by a server-owned first-order index, never request input. */
    verifiedFirstOrder: boolean;
  },
): Promise<VerifiedReferralGrant | null> {
  if (!validId(evidence.invitedUid) || !validId(evidence.firstOrderId)) {
    throw new Error("invalid referral order identity");
  }
  if (evidence.verifiedFirstOrder !== true) return null;
  const [attributionRaw, orderRaw, settingsRaw] = await Promise.all([
    read("referral_attributions", evidence.invitedUid),
    read("orders", evidence.firstOrderId),
    read("app_info", "referral_config"),
  ]);
  if (!attributionRaw || !orderRaw || !settingsRaw) return null;
  const attribution = decodeFirestoreReferralFields(attributionRaw);
  const order = decodeFirestoreReferralFields(orderRaw);
  const settings = parseReferralSettings(decodeFirestoreReferralFields(settingsRaw));
  if (attribution.invitedUid !== evidence.invitedUid ||
      order.customerId !== evidence.invitedUid ||
      order.status !== "delivered" ||
      typeof order.deliveredAtMs !== "number" ||
      !Number.isSafeInteger(order.deliveredAtMs)) return null;
  const channel = attribution.channel;
  if (channel !== "customer" && channel !== "marketer") return null;
  if (typeof attribution.inviterUid !== "string" ||
      typeof attribution.claimedAtMs !== "number") return null;
  const decision = decideReferralReward(settings.policies[channel as ReferralChannel], {
    inviterUid: attribution.inviterUid,
    invitedUid: evidence.invitedUid,
    channel,
    attributedAt: attribution.claimedAtMs,
    firstCompletedOrderAt: order.deliveredAtMs,
    previousAwards: 0,
  });
  if (!decision.eligible) return null;
  return {
    grantId: decision.grantId,
    inviterUid: attribution.inviterUid,
    invitedUid: evidence.invitedUid,
    sourceOrderId: evidence.firstOrderId,
    amount: decision.amount,
    unit: decision.unit,
    policyVersion: settings.version,
  };
}
