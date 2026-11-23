import type { ReferralChannel, ReferralPolicy, RewardUnit } from "./referrals";

/**
 * Fail-closed decoder for admin-controlled Firestore referral settings.
 * Call only with data read by the trusted Worker; never accept settings
 * supplied by a customer, marketer, or store owner request.
 */
const units: Record<ReferralChannel, readonly RewardUnit[]> = {
  customer: ["points"],
  marketer: ["cash_minor"],
  store_owner: ["cash_minor", "commission_discount_minor"],
  store_customer: ["cash_minor", "commission_discount_minor"],
};

export interface ReferralSettings {
  version: number;
  policies: Record<ReferralChannel, ReferralPolicy>;
}

export function parseReferralSettings(input: unknown): ReferralSettings {
  if (typeof input !== "object" || input === null || Array.isArray(input)) {
    throw new Error("invalid referral settings");
  }
  const obj = input as Record<string, unknown>;
  if (!Number.isSafeInteger(obj.version) || (obj.version as number) < 1) {
    throw new Error("invalid referral settings version");
  }
  const rawPolicies = obj.policies;
  if (typeof rawPolicies !== "object" || rawPolicies === null || Array.isArray(rawPolicies)) {
    throw new Error("missing referral policies");
  }
  const entries = rawPolicies as Record<string, unknown>;
  const policies = {} as Record<ReferralChannel, ReferralPolicy>;
  for (const channel of ["customer", "marketer", "store_owner", "store_customer"] as const) {
    const raw = entries[channel];
    if (channel === "store_customer" && raw === undefined) {
      policies[channel] = { enabled: false, channel, unit: "cash_minor", amount: 0 };
      continue;
    }
    if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
      throw new Error(`missing policy: ${channel}`);
    }
    const p = raw as Record<string, unknown>;
    if (typeof p.enabled !== "boolean" || p.channel !== channel ||
        !units[channel].includes(p.unit as RewardUnit) ||
        !Number.isSafeInteger(p.amount) || (p.amount as number) < 0 ||
        (p.enabled && p.amount === 0) ||
        (p.maxPerInviter !== undefined &&
          (!Number.isSafeInteger(p.maxPerInviter) || (p.maxPerInviter as number) < 0))) {
      throw new Error(`invalid policy: ${channel}`);
    }
    policies[channel] = {
      enabled: p.enabled,
      channel,
      unit: p.unit as RewardUnit,
      amount: p.amount as number,
      ...(p.maxPerInviter === undefined ? {} : { maxPerInviter: p.maxPerInviter as number }),
    };
  }
  return { version: obj.version as number, policies };
}
