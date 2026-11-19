import { afterEach, describe, expect, it, vi } from "vitest";
import { exportJWK, generateKeyPair, SignJWT } from "jose";
import worker, { appCheckMode } from "../src/index";

const PROJECT_NUMBER = "244081237486";

// مفتاح واحد لكل الملف: jose بيخزن مفاتيح JWKS في الذاكرة بين الاختبارات،
// فمفتاح جديد بنفس الـ kid كان هيفشل لسبب غلط.
const keyPairPromise = generateKeyPair("RS256", { extractable: true });

async function appCheckFixture() {
  const { publicKey, privateKey } = await keyPairPromise;
  const jwk = { ...(await exportJWK(publicKey)), kid: "test-app-check-key", alg: "RS256", use: "sig" };
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input) => {
    const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
    if (url === "https://firebaseappcheck.googleapis.com/v1/jwks") {
      return new Response(JSON.stringify({ keys: [jwk] }), {
        headers: { "content-type": "application/json" },
      });
    }
    throw new Error(`unexpected fetch in test: ${url}`);
  });
  const sign = (claims: { iss?: string; aud?: string[]; sub?: string } = {}) =>
    new SignJWT({})
      .setProtectedHeader({ alg: "RS256", kid: "test-app-check-key", typ: "JWT" })
      .setIssuer(claims.iss ?? `https://firebaseappcheck.googleapis.com/${PROJECT_NUMBER}`)
      .setAudience(claims.aud ?? [`projects/${PROJECT_NUMBER}`, "projects/wasally-12259"])
      .setSubject(claims.sub ?? "1:244081237486:android:82a134e150bb8f2ed4c2ff")
      .setIssuedAt()
      .setExpirationTime("1h")
      .sign(privateKey);
  return { sign };
}

afterEach(() => {
  vi.restoreAllMocks();
});

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

  it("enforce accepts a correctly signed App Check token and continues to the Firebase login check", async () => {
    const { sign } = await appCheckFixture();
    const env = { ...baseEnv, APP_CHECK_MODE: "enforce", FIREBASE_PROJECT_NUMBER: PROJECT_NUMBER };
    const response = await worker.fetch(
      orderRequest({ Authorization: "Bearer not-a-firebase-token", "X-Firebase-AppCheck": await sign() }),
      env as never,
    );
    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: "رمز تسجيل الدخول غير صالح أو منتهي." });
  });

  it("enforce rejects a signed token issued for another Firebase project", async () => {
    const { sign } = await appCheckFixture();
    const env = { ...baseEnv, APP_CHECK_MODE: "enforce", FIREBASE_PROJECT_NUMBER: PROJECT_NUMBER };
    const otherProject = await sign({
      iss: "https://firebaseappcheck.googleapis.com/999999999",
      aud: ["projects/999999999"],
    });
    const response = await worker.fetch(
      orderRequest({ Authorization: "Bearer x", "X-Firebase-AppCheck": otherProject }),
      env as never,
    );
    expect(response.status).toBe(401);
    expect(((await response.json()) as { error: string }).error).toContain("نسخة التطبيق");
  });
});
