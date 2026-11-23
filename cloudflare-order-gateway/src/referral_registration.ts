import { commitVerifiedAttribution } from "./referral_attribution_commit";
import { decideReferralClaim } from "./referral_claim";
import type { FirestoreTransport } from "./referral_commit";
import { decodeFirestoreReferralFields } from "./referral_firestore_values";
import { readReferralDocument } from "./referral_read";
import { parseReferralSettings } from "./referral_settings";
import { beginReferralTransaction } from "./referral_transaction";
import { isReferralCode, normalizeReferralCode } from "./referrals";

interface Registration {
  projectId: string;
  token: string;
  uid: string;
  code: string;
  createdAtMs: number;
  now: number;
}

export async function registerReferral(
  { projectId, token, uid, code: input, createdAtMs, now }: Registration,
  transport: FirestoreTransport,
): Promise<boolean> {
  const code = normalizeReferralCode(input);
  const validId = /^[A-Za-z0-9_-]{1,128}$/;
  if (!isReferralCode(code) || !validId.test(uid)) return false;
  const transaction = await beginReferralTransaction(projectId, token, transport);
  const read = async (collection: string, id: string) => {
    const raw = await readReferralDocument(projectId, collection, id, transaction, token, transport);
    return raw && decodeFirestoreReferralFields(raw);
  };
  let committed = false;
  try {
    const existing = await read("referral_attributions", uid);
    if (existing) return existing.invitedUid === uid && existing.code === code;
    const [record, config] = await Promise.all([
      read("referral_codes", code),
      read("app_info", "referral_config"),
    ]);
    if (!record || !config || typeof record.inviterUid !== "string") return false;
    if (record.channel !== "customer" && record.channel !== "marketer" && record.channel !== "store_owner") return false;
    const claim = decideReferralClaim(code, {
      code: typeof record.code === "string" ? record.code : "",
      inviterUid: record.inviterUid,
      channel: record.channel,
      active: record.active === true,
    }, {
      invitedUid: uid,
      accountCreatedAtMs: createdAtMs,
      claimAtMs: now,
      registrationWindowMs: 300_000,
      alreadyAttributed: false,
    });
    if (!claim.allowed) return false;
    const { policies } = parseReferralSettings(config);
    if (!policies[claim.channel].enabled &&
        !(claim.channel === "store_owner" && policies.store_customer.enabled)) return false;
    if (claim.channel === "marketer") {
      if (typeof record.issuedByUid !== "string" || !validId.test(record.issuedByUid) ||
          !await read("admins", record.issuedByUid)) return false;
    }
    if (claim.channel === "store_owner") {
      const owner = await read("storeOwners", claim.inviterUid);
      if (owner?.active === false || typeof owner?.storeId !== "string" || !validId.test(owner.storeId)) return false;
      const store = await read("stores", owner.storeId);
      if (store?.active !== true || store.approved !== true) return false;
    }
    await commitVerifiedAttribution(projectId, transaction, {
      invitedUid: uid,
      inviterUid: claim.inviterUid,
      code: claim.code,
      channel: claim.channel,
      claimedAtMs: now,
    }, token, transport);
    committed = true;
    return true;
  } finally {
    if (!committed) {
      const root = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;
      await transport(`${root}:rollback`, {
        method: "POST",
        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        body: JSON.stringify({ transaction }),
      }).catch(() => undefined);
    }
  }
}
