import { describe, expect, it } from "vitest";
import { normalizePayment, walletEnabled } from "../src/index";

describe("wallet payment input", () => {
  it("defaults to cash and ignores a reference for cash orders", () => {
    expect(normalizePayment(undefined, undefined)).toEqual({ method: "cash", ref: "" });
    expect(normalizePayment("cash", "TX123")).toEqual({ method: "cash", ref: "" });
  });

  it("normalizes wallet references to upper-case letters and digits", () => {
    expect(normalizePayment("vodafone_cash", " tx-12 34 56 ")).toEqual({ method: "vodafone_cash", ref: "TX123456" });
    expect(normalizePayment("instapay", "ab12cd34")).toEqual({ method: "instapay", ref: "AB12CD34" });
  });

  it("rejects unknown methods and malformed references", () => {
    expect(() => normalizePayment("bank", "TX123456")).toThrow();
    expect(() => normalizePayment("vodafone_cash", "")).toThrow();
    expect(() => normalizePayment("vodafone_cash", "AB1")).toThrow();
    expect(() => normalizePayment("vodafone_cash", "TX_123456")).toThrow();
    expect(() => normalizePayment("instapay", "A".repeat(41))).toThrow();
  });
});

describe("wallet settings", () => {
  const settings = { enabled: true, vodafoneCashNumber: "01012345678", instapayAddress: "" };

  it("requires the switch and a number/address for the chosen method", () => {
    expect(walletEnabled(settings, "vodafone_cash")).toBe(true);
    expect(walletEnabled(settings, "instapay")).toBe(false);
    expect(walletEnabled({ ...settings, enabled: false }, "vodafone_cash")).toBe(false);
    expect(walletEnabled(null, "vodafone_cash")).toBe(false);
    expect(walletEnabled({ ...settings, vodafoneCashNumber: "   " }, "vodafone_cash")).toBe(false);
  });
});
