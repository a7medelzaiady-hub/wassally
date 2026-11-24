import { decodeFirestoreReferralFields } from "./referral_firestore_values";
import { decideReferralReward } from "./referrals";
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
  const [attributionRaw, settingsRaw, firstOrderRaw] = await Promise.all([
    read("referral_attributions", evidence.invitedUid),
    read("app_info", "referral_config"),
    read("referral_first_orders", evidence.invitedUid),
  ]);
  if (!attributionRaw || !settingsRaw || !firstOrderRaw) return null;
  const firstOrder = decodeFirestoreReferralFields(firstOrderRaw);
  const collection = firstOrder.orderCollection ?? "orders";
  if (collection !== "orders" && collection !== "quick_orders") return null;
  const orderRaw = await read(collection, evidence.firstOrderId);
  if (!orderRaw) return null;
  const attribution = decodeFirestoreReferralFields(attributionRaw);
  const order = decodeFirestoreReferralFields(orderRaw);
  const settings = parseReferralSettings(decodeFirestoreReferralFields(settingsRaw));
  if (firstOrder.invitedUid !== evidence.invitedUid ||
      firstOrder.firstCompletedOrderId !== evidence.firstOrderId ||
      !Number.isSafeInteger(firstOrder.completedAtMs) ||
      (firstOrder.completedAtMs as number) <= 0) return null;
  if (attribution.invitedUid !== evidence.invitedUid ||
      typeof attribution.inviterUid !== "string" ||
      !validId(attribution.inviterUid) ||
      attribution.inviterUid === evidence.invitedUid ||
      typeof attribution.claimedAtMs !== "number" ||
      !Number.isSafeInteger(attribution.claimedAtMs) ||
      attribution.claimedAtMs <= 0 ||
      attribution.claimedAtMs > (firstOrder.completedAtMs as number) ||
      order.userId !== evidence.invitedUid ||
      order.status !== "delivered" ||
      typeof order.deliveredAt !== "number" ||
      !Number.isSafeInteger(order.deliveredAt) ||
      order.deliveredAt !== firstOrder.completedAtMs) return null;
  const channel = attribution.channel === "store_owner" ? "store_customer" : attribution.channel;
  if (channel !== "customer" && channel !== "marketer" && channel !== "store_customer") return null;
  const policy = settings.policies[channel];
  if (!policy.enabled) return null;
  if (channel === "store_customer") {
    const ownerRaw = await read("storeOwners", attribution.inviterUid);
    if (!ownerRaw) return null;
    const owner = decodeFirestoreReferralFields(ownerRaw);
    if (owner.active === false || typeof owner.storeId !== "string" || !validId(owner.storeId)) return null;
    const storeRaw = await read("stores", owner.storeId);
    if (!storeRaw) return null;
    const store = decodeFirestoreReferralFields(storeRaw);
    if (store.active !== true || store.approved !== true) return null;
  }
  const balanceRaw = await read("referral_balances", attribution.inviterUid);
  const counterField = channel === "customer" ? "customerAwardsCount" :
    channel === "marketer" ? "marketerAwardsCount" : "storeCustomerAwardsCount";
  let previousAwards = 0;
  if (balanceRaw !== null) {
    const balance = decodeFirestoreReferralFields(balanceRaw);
    const counter = balance[counterField];
    if (counter === undefined) {
      if (balance.customerAwardsCount === undefined && balance.marketerAwardsCount === undefined &&
          balance.storeOwnerAwardsCount === undefined && balance.storeCustomerAwardsCount === undefined) return null;
    } else {
      if (typeof counter !== "number" || !Number.isSafeInteger(counter) || counter < 0) return null;
      previousAwards = counter;
    }
  }
  const decision = decideReferralReward(policy, {
    inviterUid: attribution.inviterUid,
    invitedUid: evidence.invitedUid,
    channel,
    attributedAt: attribution.claimedAtMs,
    firstCompletedOrderAt: order.deliveredAt,
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
