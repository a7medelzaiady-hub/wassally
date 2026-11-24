import { describe, expect, it } from "vitest";
import { buildAdminReferralSettingsWrite } from "../src/referral_admin_settings";
const root = "projects/demo/databases/(default)/documents";
const stamp = "2026-11-23T12:00:00Z";
const settings = {
  version: 3,
  policies: {
    customer: { enabled: true, channel: "customer", unit: "points", amount: 20, maxPerInviter: 5 },
    marketer: { enabled: true, channel: "marketer", unit: "cash_minor", amount: 100 },
    store_owner: { enabled: true, channel: "store_owner", unit: "commission_discount_minor", amount: 200 },
  },
};
describe("admin referral policy write plan", () => {
  it("writes all policies with optimistic concurrency and a fixed server path", () => {
    const write = buildAdminReferralSettingsWrite(root, settings, 2, stamp);
    expect(write.update.name).toBe(`${root}/app_info/referral_config`);
    expect(write.currentDocument).toEqual({ updateTime: stamp });
    expect(write.update.fields.policies.mapValue.fields.customer.mapValue.fields.maxPerInviter)
      .toEqual({ integerValue: "5" });
  });
  it("rejects stale versions, unsafe reward channels and invalid amounts", () => {
    expect(() => buildAdminReferralSettingsWrite(root, settings, 3, stamp)).toThrow();
    expect(() => buildAdminReferralSettingsWrite(root, {
      ...settings, policies: { ...settings.policies, customer: {
        ...settings.policies.customer, unit: "cash_minor",
      } },
    }, 2, stamp)).toThrow();
    expect(() => buildAdminReferralSettingsWrite(root, {
      ...settings, policies: { ...settings.policies, marketer: {
        ...settings.policies.marketer, amount: -1,
      } },
    }, 2, stamp)).toThrow();
    expect(() => buildAdminReferralSettingsWrite(root, settings, 2, "")).toThrow();
    expect(() => buildAdminReferralSettingsWrite(root, settings, 2, "2026-11-23T12:00:00")).toThrow();
    expect(() => buildAdminReferralSettingsWrite(root, settings, 2, "2026-11-23T12:00:00Zjunk")).toThrow();
    expect(() => buildAdminReferralSettingsWrite(root, settings, 2, "2026-11-23T12:00:00.123456789Z")).not.toThrow();
    expect(() => buildAdminReferralSettingsWrite("bad/root", settings, 2, stamp)).toThrow();
  });
});
