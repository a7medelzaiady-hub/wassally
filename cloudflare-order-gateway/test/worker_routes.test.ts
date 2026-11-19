import { describe, expect, it } from "vitest";
import worker, { orderStatusPushMessage } from "../src/index";

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

  it("requires Firebase authentication before sending order status pushes", async () => {
    const response = await worker.fetch(
      new Request("https://worker.test/v1/orders/order_123/events", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ status: "preparing" }),
      }),
      env,
    );
    expect(response.status).toBe(401);
  });

  it("rejects unsupported order notification events", async () => {
    const response = await worker.fetch(
      new Request("https://worker.test/v1/orders/order_123/events", {
        method: "POST",
        headers: {
          Authorization: "Bearer not-a-valid-jwt",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ status: "private_contact" }),
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

  it("does not expose order creation through unsupported HTTP methods", async () => {
    const response = await worker.fetch(
      new Request("https://worker.test/v1/orders", { method: "GET" }),
      env,
    );
    expect(response.status).toBe(404);
  });
});

describe("order status push payload", () => {
  it("contains only navigation identifiers and status, never customer contact data", () => {
    const payload = orderStatusPushMessage("fcm-token", "order_123", "on_the_way");
    expect(payload.message.data).toEqual({
      type: "status",
      orderId: "order_123",
      status: "on_the_way",
    });
    expect(JSON.stringify(payload)).not.toContain("phone");
    expect(JSON.stringify(payload)).not.toContain("address");
    expect(payload.message.android.priority).toBe("HIGH");
  });
});
