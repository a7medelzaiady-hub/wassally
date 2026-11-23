import { parseReferralSettings } from "./referral_settings";

/**
 * Prepare an admin-only settings update. The caller MUST verify the Firebase
 * actor's administrator role and read the current document in the same
 * Firestore transaction before committing. No client-provided document path.
 * A version precondition prevents lost concurrent admin edits.
 */
export function buildAdminReferralSettingsWrite(
  root: string,
  input: unknown,
  currentVersion: number,
  currentUpdateTime: string | null,
) {
  if (!/^projects\/[A-Za-z0-9_-]+\/databases\/\(default\)\/documents$/.test(root)) {
    throw new Error("invalid Firestore root");
  }
  const initial = currentVersion === 0 && currentUpdateTime === null;
  if (!initial && (!Number.isSafeInteger(currentVersion) || currentVersion < 1 ||
      typeof currentUpdateTime !== "string" ||
      !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:Z|[+-]\d{2}:\d{2})$/.test(currentUpdateTime) ||
      !Number.isFinite(Date.parse(currentUpdateTime)))) {
    throw new Error("missing trusted current settings");
  }
  const settings = parseReferralSettings(input);
  if (settings.version !== currentVersion + 1) {
    throw new Error("settings version must increment by one");
  }
  const value = (n: number) => ({ integerValue: String(n) });
  const policies = Object.fromEntries(
    Object.entries(settings.policies).map(([channel, p]) => [
      channel, { mapValue: { fields: {
        enabled: { booleanValue: p.enabled },
        channel: { stringValue: channel },
        unit: { stringValue: p.unit },
        amount: value(p.amount),
        ...(p.maxPerInviter === undefined ? {} : { maxPerInviter: value(p.maxPerInviter) }),
      } } },
    ]),
  );
  return {
    update: {
      name: `${root}/app_info/referral_config`,
      fields: {
        version: value(settings.version),
        policies: { mapValue: { fields: policies } },
        ...(settings.redemption ? { redemption: { mapValue: { fields: {
          pointValueMinor: value(settings.redemption.pointValueMinor),
          maxDiscountMinor: value(settings.redemption.maxDiscountMinor),
        } } } } : {}),
      },
    },
    currentDocument: initial ? { exists: false } : { updateTime: currentUpdateTime },
  };
}
