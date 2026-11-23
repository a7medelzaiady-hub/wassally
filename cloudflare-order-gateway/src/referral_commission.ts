export function commissionAmounts(dueMinor: number, balanceMinor: unknown) {
  if (!Number.isSafeInteger(dueMinor) || dueMinor < 1 || dueMinor > 10_000_000) {
    throw new Error("invalid commission due");
  }
  const credit = balanceMinor ?? 0;
  if (typeof credit !== "number" || !Number.isSafeInteger(credit) || credit < 0) {
    throw new Error("invalid commission balance");
  }
  const discountMinor = Math.min(dueMinor, credit);
  return { dueMinor, discountMinor, payableMinor: dueMinor - discountMinor };
}
