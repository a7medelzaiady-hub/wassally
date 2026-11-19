import { describe, expect, it } from "vitest";
import worker, { appCheckMode } from "../src/index";

const baseEnv = {
  FIREBASE_PROJECT_ID: "wasally-test",
  FIREBASE_SERVICE_ACCOUNT_EMAIL: "worker-test@wasally-test.iam.gserviceaccount.com",
  FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY: "not-used-for-invalid-token-tests",
};

function orderRequest(headers: Record<string, string> = {}) {
  return new Request("https://worker.test/v1/orders", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: "{}",
  });
}

describe("App Check mode", () => {
  it("defaults to off for missing or unknown values", () => {
    expect(appCheckMode(undefined)).toBe("off");
    expect(appCheckMode("")).toBe("off");
    expect(appCheckMode("yes")).toBe("off");
    expect(appCheckMode(" Monitor ")).toBe("monitor");
    expect(appCheckMode("ENFORCE")).toBe("enforce");
  });

  it("off keeps the existing behaviour (bearer token check runs first)", async () => {
    const response = await worker.fetch(orderRequest(), baseEnv as never);
    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: "سجّل الدخول من جديد." });
  });

  it("monitor never blocks a request that lacks an App Check token", async () => {
    const env = { ...baseEnv, APP_CHECK_MODE: "monitor", FIREBASE_PROJECT_NUMBER: "244081237486" };
    const response = await worker.fetch(orderRequest(), env as never);
    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: "سجّل الدخول من جديد." });
  });

  it("enforce rejects a request without an App Check token before any other work", async () => {
    const env = { ...baseEnv, APP_CHECK_MODE: "enforce", FIREBASE_PROJECT_NUMBER: "244081237486" };
    const response = await worker.fetch(orderRequest({ Authorization: "Bearer x" }), env as never);
    expect(response.status).toBe(401);
    const body = await response.json() as { error: string };
    expect(body.error).toContain("نسخة التطبيق");
  });

  it("enforce rejects a malformed App Check token", async () => {
    const env = { ...baseEnv, APP_CHECK_MODE: "enforce", FIREBASE_PROJECT_NUMBER: "244081237486" };
    const response = await worker.fetch(
      orderRequest({ Authorization: "Bearer x", "X-Firebase-AppCheck": "not-a-jwt" }),
      env as never,
    );
    expect(response.status).toBe(401);
  });

  it("enforce fails closed when the project number is not configured", async () => {
    const env = { ...baseEnv, APP_CHECK_MODE: "enforce" };
    const response = await worker.fetch(orderRequest(), env as never);
    expect(response.status).toBe(503);
  });
});
