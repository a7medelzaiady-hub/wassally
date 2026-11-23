import { decodeFirestoreReferralFields } from "./referral_firestore_values";
import { decideReferralReward, type ReferralChannel } from "./referrals";
import { parseReferralSettings } from "./referral_settings";
import type { VerifiedReferralGrant } from "./referral_grants";

type Read = (collection: string, id: string) => Promise<Record<string, unknown> | null>;
const validId = (v: string) => /^[A-Za-z0-9_-]{1,128}$/.test(v);

/**
 * Canonical customer/marketer award verifier for the isolated referral schema.
 * This is not wired into the public Worker router. A trusted handler must
 * maintain a server-owned immutable first-successful-order index.
 * The index is read within the SAME Firestore transaction; a caller-supplied
 * boolean is never accepted as evidence that an order was first.
 */
export async function verifyFirstOrderReferral(
  read: Read,
  evidence: {
    invitedUid: string;
    firstOrderId: string;
  },
): Promise<VerifiedReferralGrant | null> {
  if (!validId(evidence.invitedUid) || !validId(evidence.firstOrderId)) {
    throw new Error("invalid referral order identity");
  }
  const [attributionRaw, orderRaw, settingsRaw, firstOrderRaw] = await Promise.all([
    read("referral_attributions", evidence.invitedUid),
    read("orders", evidence.firstOrderId),
    read("app_info", "referral_config"),
    read("referral_first_orders", evidence.invitedUid),
  ]);
  if (!attributionRaw || !orderRaw || !settingsRaw || !firstOrderRaw) return null;
  const attribution = decodeFirestoreReferralFields(attributionRaw);
  const order = decodeFirestoreReferralFields(orderRaw);
  const settings = parseReferralSettings(decodeFirestoreReferralFields(settingsRaw));
  const firstOrder = decodeFirestoreReferralFields(firstOrderRaw);
  if (firstOrder.invitedUid !== evidence.invitedUid ||
      firstOrder.firstCompletedOrderId !== evidence.firstOrderId ||
      !Number.isSafeInteger(firstOrder.completedAtMs) ||
      (firstOrder.completedAtMs as number) <= 0) return null;
  if (attribution.invitedUid !== evidence.invitedUid ||
      order.customerId !== evidence.invitedUid ||
      order.status !== "delivered" ||
      typeof order.deliveredAtMs !== "number" ||
      !Number.isSafeInteger(order.deliveredAtMs) ||
      order.deliveredAtMs !== firstOrder.completedAtMs) return null;
  const channel = attribution.channel;
  if (channel !== "customer" && channel !== "marketer") return null;
  if (typeof attribution.inviterUid !== "string" ||
      typeof attribution.claimedAtMs !== "number") return null;
  const policy = settings.policies[channel as ReferralChannel];
  const balanceRaw = await read("referral_balances", attribution.inviterUid as string);
  let previousAwards = 0;
  if (balanceRaw !== null) {
    const balance = decodeFirestoreReferralFields(balanceRaw);
    if (typeof balance.awardsCount !== "number" ||
        !Number.isSafeInteger(balance.awardsCount) || balance.awardsCount < 0) return null;
    previousAwards = balance.awardsCount;
  }
  const decision = decideReferralReward(policy, {
    inviterUid: attribution.inviterUid,
    invitedUid: evidence.invitedUid,
    channel,
    attributedAt: attribution.claimedAtMs,
    firstCompletedOrderAt: order.deliveredAtMs,
    previousAwards,
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
