import { describe, expect, it, vi } from "vitest";
import { beginReferralTransaction } from "../src/referral_transaction";
import type { FirestoreTransport } from "../src/referral_commit";

describe("Firestore referral transaction", () => {
  it("opens a read-write transaction using service OAuth", async () => {
    const transport = vi.fn<FirestoreTransport>(async () => ({
      ok: true, status: 200, text: async () => JSON.stringify({ transaction: "abc+/==" }),
    }));
    await expect(beginReferralTransaction("demo-project", "service-token", transport))
      .resolves.toBe("abc+/==");
    const [url, init] = transport.mock.calls[0]!;
    expect(url).toContain("demo-project/databases/(default)/documents:beginTransaction");
    expect(init.headers.Authorization).toBe("Bearer service-token");
    expect(JSON.parse(init.body)).toEqual({ options: { readWrite: {} } });
  });

  it("fails closed on bad input and server errors", async () => {
    const ok = vi.fn<FirestoreTransport>(async () => ({
      ok: true, status: 200, text: async () => "{}",
    }));
    await expect(beginReferralTransaction("bad/project", "token", ok)).rejects.toThrow();
    await expect(beginReferralTransaction("demo", "", ok)).rejects.toThrow();
    expect(ok).not.toHaveBeenCalled();
    await expect(beginReferralTransaction("demo", "token", ok)).rejects.toThrow("transaction token");
    const denied = vi.fn<FirestoreTransport>(async () => ({
      ok: false, status: 403, text: async () => "denied",
    }));
    await expect(beginReferralTransaction("demo", "token", denied)).rejects.toThrow();
  });
});
