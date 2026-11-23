/**
 * Builds a single atomic Firestore REST commit for a verified referral grant.
 * The caller MUST fetch and validate the canonical order, policy, attribution,
 * inviter, and prior grant using a Firestore transaction before invoking this.
 * This module does not authenticate, fetch documents, or send requests.
 *
 * Atomic create-only grant + increment balance in one commit:
 * - precondition exists=false on grant prevents duplicate awards
 * - balance uses Firestore increment transform
 * - no balance update survives if grant create fails
 *
 * Caller must use the same Firestore transaction for its reads and this commit,
 * and retry aborted transactions by re-reading canonical facts.
 */
import type { RewardUnit } from "./referrals";

export interface VerifiedReferralGrant {
  grantId: string;
  inviterUid: string;
  invitedUid: string;
  sourceOrderId: string;
  amount: number;
  unit: RewardUnit;
  policyVersion: number;
}

export interface FirestoreWrite {
  update?: {
    name: string;
    fields: Record<string, unknown>;
  };
  currentDocument?: { exists: boolean };
  transform?: {
    document: string;
    fieldTransforms: Array<{
      fieldPath: string;
      increment: { integerValue: string };
    }>;
  };
}

const validId = (id: string) => /^[A-Za-z0-9_-]{1,128}$/.test(id);
const stringValue = (value: string) => ({ stringValue: value });
const integerValue = (value: number) => ({ integerValue: String(value) });

export function buildReferralGrantWrites(
  databaseRoot: string,
  grant: VerifiedReferralGrant,
): FirestoreWrite[] {
  if (!/^projects\/[A-Za-z0-9_-]+\/databases\/\(default\)\/documents$/.test(databaseRoot)) {
    throw new Error("invalid Firestore database root");
  }
  for (const id of [grant.grantId, grant.inviterUid, grant.invitedUid, grant.sourceOrderId]) {
    if (!validId(id)) throw new Error("invalid referral identifier");
  }
  if (grant.inviterUid === grant.invitedUid) throw new Error("self referral");
  if (!Number.isSafeInteger(grant.amount) || grant.amount <= 0) {
    throw new Error("invalid reward amount");
  }
  if (!Number.isSafeInteger(grant.policyVersion) || grant.policyVersion < 1) {
    throw new Error("invalid policy version");
  }
  const balanceField: Record<RewardUnit, string> = {
    points: "points",
    cash_minor: "cashMinor",
    commission_discount_minor: "commissionDiscountMinor",
  };
  const field = balanceField[grant.unit];
  if (!field) throw new Error("invalid reward unit");
  return [
    {
      update: {
        name: `${databaseRoot}/referral_grants/${grant.grantId}`,
        fields: {
          inviterUid: stringValue(grant.inviterUid),
          invitedUid: stringValue(grant.invitedUid),
          sourceOrderId: stringValue(grant.sourceOrderId),
          unit: stringValue(grant.unit),
          amount: integerValue(grant.amount),
          policyVersion: integerValue(grant.policyVersion),
          status: stringValue("granted"),
        },
      },
      currentDocument: { exists: false },
    },
    {
      transform: {
        document: `${databaseRoot}/referral_balances/${grant.inviterUid}`,
        fieldTransforms: [{
          fieldPath: field,
          increment: integerValue(grant.amount),
        }],
      },
    },
  ];
}
