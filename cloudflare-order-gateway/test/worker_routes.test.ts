import { describe, expect, it, vi } from "vitest";
import worker from "../src/index";

const envConfig = {
  FIREBASE_PROJECT_ID: "wasally-test",
  FIREBASE_SERVICE_ACCOUNT_EMAIL: "worker-test@wasally-test.iam.gserviceaccount.com",
  FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY: "not-used-for-invalid-token-tests",
};
const env = envConfig as never;

describe("Worker order gateway route hardening", () => {
  it("exposes a minimal health response without leaking configuration", async () => {
    const response = await worker.fetch(
      new Request("https://worker.test/health"),
      env,
    );
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      ok: true,
      service: "wasally-order-gateway",
    });
  });

  it("rejects order creation when the Firebase bearer token is missing", async () => {
    const response = await worker.fetch(
      new Request("https://worker.test/v1/orders", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: "{}",
      }),
      env,
    );
    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: "سجّل الدخول من جديد." });
  });

  it("rejects malformed Firebase tokens before any Firestore operation", async () => {
    const response = await worker.fetch(
      new Request("https://worker.test/v1/orders", {
        method: "POST",
        headers: {
          Authorization: "Bearer not-a-valid-jwt",
          "Content-Type": "application/json",
        },
        body: "{}",
      }),
      env,
    );
    expect(response.status).toBe(401);
  });

  it("protects order editing with the same Firebase authentication gate", async () => {
    const response = await worker.fetch(
      new Request("https://worker.test/v1/orders/order_123", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: "{}",
      }),
      env,
    );
    expect(response.status).toBe(401);
  });

  it("rejects disallowed browser origins before processing order requests", async () => {
    const response = await worker.fetch(
      new Request("https://worker.test/v1/orders", {
        method: "POST",
        headers: {
          Origin: "https://attacker.example",
          "Content-Type": "application/json",
        },
        body: "{}",
      }),
      { ...envConfig, ALLOWED_ORIGINS: "https://wasally.example" } as never,
    );
    expect(response.status).toBe(403);
  });

  it("never contacts Firebase for unauthenticated order writes", async () => {
    const upstream = vi.spyOn(globalThis, "fetch");
    try {
      for (const [method, path] of [
        ["POST", "/v1/orders"],
        ["PATCH", "/v1/orders/order_123"],
      ]) {
        const response = await worker.fetch(
          new Request("https://worker.test" + path, {
            method,
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ orderId: "order_123", expectedTotal: 1 }),
          }),
          env,
        );
        expect(response.status).toBe(401);
      }
      expect(upstream).not.toHaveBeenCalled();
    } finally {
      upstream.mockRestore();
    }
  });

  it("does not expose order creation through unsupported HTTP methods", async () => {
    const response = await worker.fetch(
      new Request("https://worker.test/v1/orders", { method: "GET" }),
      env,
    );
    expect(response.status).toBe(404);
  });
});
