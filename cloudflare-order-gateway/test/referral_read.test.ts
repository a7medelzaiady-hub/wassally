import { describe, expect, it, vi } from "vitest";
import { readReferralDocument } from "../src/referral_read";
import type { FirestoreTransport } from "../src/referral_commit";

const root = "projects/demo/databases/(default)/documents";
const path = `${root}/referral_grants/grant1`;
const mock = (body: string, ok = true) =>
  vi.fn<FirestoreTransport>(async () => ({
    ok, status: ok ? 200 : 403, text: async () => body,
  }));

describe("transaction-scoped referral reads", () => {
  it("reads the expected canonical document with transaction token", async () => {
    const transport = mock(JSON.stringify([{ found: {
      name: path, fields: { status: { stringValue: "granted" } },
    } }]));
    await expect(readReferralDocument("demo", "referral_grants", "grant1",
      "abc==", "oauth", transport)).resolves.toEqual({
      status: { stringValue: "granted" },
    });
    const [url, init] = transport.mock.calls[0]!;
    expect(url).toContain(":batchGet");
    expect(JSON.parse(init.body)).toEqual({ documents: [path], transaction: "abc==" });
  });

  it("distinguishes a missing grant from failed or malformed reads", async () => {
    await expect(readReferralDocument("demo", "referral_grants", "grant1",
      "abc==", "oauth", mock(JSON.stringify({ missing: path })))).resolves.toBeNull();
    for (const response of [
      mock("denied", false),
      mock("{}"),
      mock(JSON.stringify({ found: { name: path + "evil", fields: {} } })),
      mock("not json"),
    ]) {
      await expect(readReferralDocument("demo", "referral_grants", "grant1",
        "abc==", "oauth", response)).rejects.toThrow();
    }
  });

  it("rejects unsafe paths and missing credentials without network calls", async () => {
    const transport = mock("{}");
    await expect(readReferralDocument("demo", "orders/x", "id",
      "abc==", "oauth", transport)).rejects.toThrow();
    await expect(readReferralDocument("demo", "orders", "id",
      "", "oauth", transport)).rejects.toThrow();
    await expect(readReferralDocument("demo", "orders", "id",
      "abc==", "", transport)).rejects.toThrow();
    expect(transport).not.toHaveBeenCalled();
  });
});
