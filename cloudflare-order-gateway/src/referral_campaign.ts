import { buildReferralCodeReservation } from "./referral_codes";
import type { FirestoreTransport } from "./referral_commit";
import { decodeFirestoreReferralFields } from "./referral_firestore_values";
import { readReferralDocument } from "./referral_read";
import { beginReferralTransaction } from "./referral_transaction";
import { isReferralCode, type CodeReferralChannel } from "./referrals";

type CodeOwner = { uid: string; issuerUid: string; channel: CodeReferralChannel };

export async function getOrIssueReferralCode(
  projectId: string,
  token: string,
  owner: CodeOwner,
  transport: FirestoreTransport,
): Promise<string> {
  const collection = `referral_${owner.channel}_codes`;
  const root = `projects/${projectId}/databases/(default)/documents`;
  const post = (operation: string, data: unknown) => transport(
    `https://firestore.googleapis.com/v1/${root}:${operation}`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify(data),
    },
  );
  for (let attempt = 0; attempt < 3; attempt++) {
    const transaction = await beginReferralTransaction(projectId, token, transport);
    let committed = false;
    try {
      const existing = await readReferralDocument(projectId, collection, owner.uid, transaction, token, transport);
      if (existing) {
        const { code } = decodeFirestoreReferralFields(existing);
        if (typeof code === "string" && isReferralCode(code)) return code;
        throw new Error("Invalid referral code mapping");
      }
      const code = [...crypto.getRandomValues(new Uint8Array(6))]
        .map((value) => value.toString(16).padStart(2, "0")).join("").toUpperCase();
      const reservation = buildReferralCodeReservation(root, {
        code, inviterUid: owner.uid, channel: owner.channel,
        issuedByUid: owner.issuerUid, issuedAtMs: Date.now(),
        issuerIsAdmin: owner.channel === "marketer",
      });
      const commit = await post("commit", { transaction, writes: [
        reservation,
        {
          update: { name: `${root}/${collection}/${owner.uid}`, fields: { code: { stringValue: code } } },
          currentDocument: { exists: false },
        },
      ] });
      if (commit.ok) {
        committed = true;
        return code;
      }
      if (![409, 412].includes(commit.status)) throw new Error("Could not issue referral code");
    } finally {
      if (!committed) await post("rollback", { transaction }).catch(() => undefined);
    }
  }
  throw new Error("Referral code transaction conflict");
}
