import { expect, it } from "vitest";
import { getOrIssueReferralCode } from "../src/referral_campaign";
import { registerReferral } from "../src/referral_registration";
import { settleCustomerDelivery } from "../src/referral_delivery";
import { updateReferralPayout } from "../src/referral_payout";

const emulator = process.env.FIRESTORE_EMULATOR_HOST;

it.skipIf(!emulator)("uses real Firestore REST transactions from code reservation to recorded cash transfer", async () => {
  const project = "demo-wasally";
  const api = `http://${emulator}/v1`;
  const root = api + `/projects/${project}/databases/(default)/documents`;
  const headers = { Authorization: "Bearer owner", "Content-Type": "application/json" };
  const transport: typeof fetch = (input, init) => fetch(String(input).replace("https://firestore.googleapis.com/v1", api), init);
  const str = (stringValue: string) => ({ stringValue });
  const int = (n: number) => ({ integerValue: String(n) });
  const set = async (path: string, fields: Record<string, unknown>) => {
    const result = await fetch(root + "/" + path, { method: "PATCH", headers, body: JSON.stringify({ fields }) });
    expect(result.ok, await result.text()).toBe(true);
  };
  const code = await getOrIssueReferralCode(project, "owner", {
    uid: "marketer-stage", issuerUid: "admin-stage", channel: "marketer",
  }, transport);
  const tier = (channel: string, unit: string) => ({ mapValue: { fields: {
    channel: str(channel), unit: str(unit), amount: int(1000), enabled: { booleanValue: true },
  } } });
  await set("admins/admin-stage", { configured: { booleanValue: true } });
  await set("app_info/referral_config", { version: int(1), policies: { mapValue: { fields: {
    customer: tier("customer", "points"), marketer: tier("marketer", "cash_minor"),
    store_owner: tier("store_owner", "cash_minor"),
  } } } });
  const uid = "invited-stage";
  const now = Date.now();
  expect(await registerReferral({ projectId: project, token: "owner", uid, code, now, createdAtMs: now - 500 }, transport)).toBe(true);
  await set("orders/order-stage", {
    userId: str(uid), status: str("delivered"),
    deliveredAt: { timestampValue: new Date(now + 1000).toISOString() },
  });
  await set("quick_orders/quick-stage", {
    userId: str(uid), status: str("delivered"),
    deliveredAt: { timestampValue: new Date(now + 800).toISOString() },
  });
  await settleCustomerDelivery(project, "owner", uid, transport);
  await settleCustomerDelivery(project, "owner", uid, transport);
  const granted = await fetch(root + "/referral_grants/marketer_invited-stage", { headers });
  expect(await granted.json()).toMatchObject({ fields: { sourceOrderId: str("quick-stage") } });
  const payout = await updateReferralPayout(project, "owner", {
    kind: "request", uid: "marketer-stage", requestId: "8899aabbccdd8899aabbccdd",
  }, transport);
  expect(payout.amountMinor).toBe(1000);
  await updateReferralPayout(project, "owner", {
    kind: "claim", payoutId: payout.payoutId as string, adminUid: "admin-stage",
  }, transport);
  expect(await updateReferralPayout(project, "owner", {
    kind: "paid", payoutId: payout.payoutId as string, adminUid: "admin-stage", reference: "transfer-test-1",
  }, transport)).toMatchObject({ status: "paid", amountMinor: 1000 });
}, 20000);
