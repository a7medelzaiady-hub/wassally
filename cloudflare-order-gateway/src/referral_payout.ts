import type { FirestoreTransport } from "./referral_commit";
import { decodeFirestoreReferralFields } from "./referral_firestore_values";
import { readReferralDocument } from "./referral_read";
import { beginReferralTransaction } from "./referral_transaction";

export class ReferralPayoutConflict extends Error {}

type PayoutAction =
  | { kind: "request"; uid: string; requestId: string }
  | { kind: "claim"; payoutId: string; adminUid: string }
  | { kind: "paid" | "rejected"; payoutId: string; adminUid: string; reference: string };

export async function updateReferralPayout(
  projectId: string,
  token: string,
  action: PayoutAction,
  transport: FirestoreTransport,
): Promise<Record<string, unknown>> {
  const payoutId = action.kind === "request" ? `${action.uid}_${action.requestId}` : action.payoutId;
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(payoutId)) throw new Error("Invalid payout ID");
  const root = `projects/${projectId}/databases/(default)/documents`;
  const post = (operation: string, data: unknown) => transport(
    `https://firestore.googleapis.com/v1/${root}:${operation}`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify(data),
    },
  );
  const transaction = await beginReferralTransaction(projectId, token, transport);
  const read = async (collection: string, id: string) => {
    const raw = await readReferralDocument(projectId, collection, id, transaction, token, transport);
    return raw && decodeFirestoreReferralFields(raw);
  };
  const book = `${root}/referral_payouts/${payoutId}`;
  const value = (stringValue: string) => ({ stringValue });
  const integer = (n: number) => ({ integerValue: String(n) });
  const balanceChange = (uid: string, amount: number) => ({
    transform: {
      document: `${root}/referral_balances/${uid}`,
      fieldTransforms: [{ fieldPath: "cashMinor", increment: integer(amount) }],
    },
  });
  let committed = false;
  try {
    const existing = await read("referral_payouts", payoutId);
    let writes: unknown[];
    let outcome: Record<string, unknown>;
    if (action.kind === "request") {
      if (existing) {
        if (existing.uid !== action.uid) throw new ReferralPayoutConflict();
        return { payoutId, status: existing.status, amountMinor: existing.amountMinor };
      }
      const [balance, pending] = await Promise.all([
        read("referral_balances", action.uid),
        read("referral_payout_pending", action.uid),
      ]);
      const amount = balance?.cashMinor;
      if (pending || typeof amount !== "number" || !Number.isSafeInteger(amount) || amount <= 0) {
        throw new ReferralPayoutConflict();
      }
      writes = [
        {
          update: { name: book, fields: {
            uid: value(action.uid), status: value("pending"), amountMinor: integer(amount),
          } },
          updateTransforms: [{ fieldPath: "requestedAt", setToServerValue: "REQUEST_TIME" }],
          currentDocument: { exists: false },
        },
        {
          update: { name: `${root}/referral_payout_pending/${action.uid}`, fields: { payoutId: value(payoutId) } },
          currentDocument: { exists: false },
        },
        balanceChange(action.uid, -amount),
      ];
      outcome = { payoutId, status: "pending", amountMinor: amount };
    } else {
      if (!existing) throw new ReferralPayoutConflict();
      const { uid, amountMinor, status } = existing;
      if (typeof uid !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(uid) ||
          typeof amountMinor !== "number" || !Number.isSafeInteger(amountMinor) || amountMinor <= 0) {
        throw new Error("Invalid payout record");
      }
      const pending = await read("referral_payout_pending", uid);
      if (action.kind === "claim") {
        outcome = { payoutId, status: "processing", amountMinor };
        if (status === "processing" && existing.processingBy === action.adminUid) return outcome;
        if (status !== "pending" || pending?.payoutId !== payoutId) throw new ReferralPayoutConflict();
        writes = [{
          update: { name: book, fields: { status: value("processing"), processingBy: value(action.adminUid) } },
          updateMask: { fieldPaths: ["status", "processingBy"] },
          updateTransforms: [{ fieldPath: "processingAt", setToServerValue: "REQUEST_TIME" }],
        }];
      } else {
        outcome = { payoutId, status: action.kind, amountMinor };
        if (status === action.kind && existing.reference === action.reference &&
            existing.resolvedBy === action.adminUid) return outcome;
        if (status !== "processing" || existing.processingBy !== action.adminUid ||
            pending?.payoutId !== payoutId) throw new ReferralPayoutConflict();
        writes = [
          {
            update: { name: book, fields: {
              status: value(action.kind), resolvedBy: value(action.adminUid), reference: value(action.reference),
            } },
            updateMask: { fieldPaths: ["status", "resolvedBy", "reference"] },
            updateTransforms: [{ fieldPath: "resolvedAt", setToServerValue: "REQUEST_TIME" }],
          },
          { delete: `${root}/referral_payout_pending/${uid}` },
          ...(action.kind === "rejected" ? [balanceChange(uid, amountMinor)] : []),
        ];
      }
    }
    const commit = await post("commit", { transaction, writes });
    if (commit.status === 409 || commit.status === 412) throw new ReferralPayoutConflict();
    if (!commit.ok) throw new Error("Could not update payout");
    committed = true;
    return outcome;
  } finally {
    if (!committed) await post("rollback", { transaction }).catch(() => undefined);
  }
}
