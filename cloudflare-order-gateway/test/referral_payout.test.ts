import { expect, it } from "vitest";
import { ReferralPayoutConflict, updateReferralPayout } from "../src/referral_payout";
import type { FirestoreTransport } from "../src/referral_commit";

const root = "projects/demo/databases/(default)/documents/";
const client = "marketer";
const requestId = "aabbccddeeffaabbccddeeff";
const payoutId = `${client}_${requestId}`;
const integer = (amount: number) => ({ integerValue: String(amount) });

function setup() {
  const docs = new Map<string, Record<string, unknown>>([
    [root + "referral_balances/marketer", { cashMinor: integer(1200) }],
  ]);
  const transport: FirestoreTransport = async (url, init) => {
    if (url.endsWith(":beginTransaction")) return Response.json({ transaction: "abc" });
    const body = JSON.parse(init.body);
    expect(body.transaction).toBe("abc");
    if (url.endsWith(":batchGet")) {
      const [name] = body.documents;
      const fields = docs.get(name);
      return Response.json([{ ...(fields ? { found: { name, fields } } : { missing: name }) }]);
    }
    if (url.endsWith(":rollback")) return Response.json({});
    for (const write of body.writes) {
      if (write.update) {
        const { name, fields } = write.update;
        if (write.currentDocument?.exists === false) expect(docs.has(name)).toBe(false);
        docs.set(name, { ...docs.get(name), ...fields });
      } else if (write.transform) {
        const { document, fieldTransforms } = write.transform;
        const balance = docs.get(document)!;
        const amount = Number((balance.cashMinor as { integerValue: string }).integerValue);
        balance.cashMinor = integer(amount + Number(fieldTransforms[0].increment.integerValue));
      } else if (write.delete) {
        docs.delete(write.delete);
      }
    }
    return Response.json({});
  };
  const request = () => updateReferralPayout("demo", "token", { kind: "request", uid: client, requestId }, transport);
  const claim = (adminUid = "admin") => updateReferralPayout("demo", "token", { kind: "claim", payoutId, adminUid }, transport);
  const resolve = (kind: "paid" | "rejected") => updateReferralPayout("demo", "token", {
    kind, payoutId, adminUid: "admin", reference: "verified reference",
  }, transport);
  const balance = () => docs.get(root + "referral_balances/marketer")?.cashMinor;
  return { request, claim, resolve, balance, transport };
}

it("reserves cash once, records a manual transfer and makes the same request safe to retry", async () => {
  const { request, claim, resolve, balance, transport } = setup();
  expect(await request()).toEqual({ payoutId, status: "pending", amountMinor: 1200 });
  expect(await request()).toMatchObject({ status: "pending" });
  expect(balance()).toEqual(integer(0));
  await expect(updateReferralPayout("demo", "token", {
    kind: "request", uid: client, requestId: "000000000000000000000000",
  }, transport)).rejects.toBeInstanceOf(ReferralPayoutConflict);
  await expect(resolve("paid")).rejects.toBeInstanceOf(ReferralPayoutConflict);
  expect(await claim()).toMatchObject({ status: "processing" });
  await expect(claim("other-admin")).rejects.toBeInstanceOf(ReferralPayoutConflict);
  expect(await resolve("paid")).toMatchObject({ status: "paid" });
  expect(await resolve("paid")).toMatchObject({ status: "paid" });
  expect(await request()).toMatchObject({ status: "paid" });
  await expect(resolve("rejected")).rejects.toBeInstanceOf(ReferralPayoutConflict);
  expect(balance()).toEqual(integer(0));
});

it("returns the reserved cash exactly once when a payout is rejected", async () => {
  const { request, claim, resolve, balance } = setup();
  await request();
  await claim();
  await resolve("rejected");
  await resolve("rejected");
  expect(balance()).toEqual(integer(1200));
});
