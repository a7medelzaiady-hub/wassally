import type { ReferralSettings } from "./referral_settings";

export function quoteReferralPoints(
  policy: ReferralSettings["redemption"],
  balance: unknown,
  itemsSubtotalMinor: number,
) {
  if (!Number.isSafeInteger(itemsSubtotalMinor) || itemsSubtotalMinor < 0) {
    throw new Error("invalid merchandise subtotal");
  }
  const availablePoints = balance ?? 0;
  if (typeof availablePoints !== "number" ||
      !Number.isSafeInteger(availablePoints) || availablePoints < 0) {
    throw new Error("invalid points balance");
  }
  if (!policy) return { points: 0, discountMinor: 0 };
  const eligibleMinor = Math.min(policy.maxDiscountMinor, itemsSubtotalMinor);
  const points = Math.min(availablePoints, Math.floor(eligibleMinor / policy.pointValueMinor));
  return { points, discountMinor: points * policy.pointValueMinor };
}
