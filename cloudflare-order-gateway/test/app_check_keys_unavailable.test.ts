// ملف منفصل عمدًا: jose بيخزن مفاتيح JWKS في ذاكرة الموديول، فلازم موديول جديد
// مفيش فيه مفاتيح متخزنة عشان نختبر فشل جلب المفاتيح فعلًا.
import { afterEach, describe, expect, it, vi } from "vitest";
import { exportJWK, generateKeyPair, SignJWT } from "jose";
import worker from "../src/index";

const PROJECT_NUMBER = "244081237486";
const env = {
  FIREBASE_PROJECT_ID: "wasally-test",
  FIREBASE_SERVICE_ACCOUNT_EMAIL: "worker-test@wasally-test.iam.gserviceaccount.com",
  FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY: "not-used-for-invalid-token-tests",
  APP_CHECK_MODE: "enforce",
  FIREBASE_PROJECT_NUMBER: PROJECT_NUMBER,
};

afterEach(() => {
  vi.restoreAllMocks();
});

async function signedToken(kid: string) {
  const { publicKey, privateKey } = await generateKeyPair("RS256", { extractable: true });
  await exportJWK(publicKey);
  return new SignJWT({})
    .setProtectedHeader({ alg: "RS256", kid, typ: "JWT" })
    .setIssuer(`https://firebaseappcheck.googleapis.com/${PROJECT_NUMBER}`)
    .setAudience([`projects/${PROJECT_NUMBER}`])
    .setSubject("1:244081237486:android:82a134e150bb8f2ed4c2ff")
    .setIssuedAt()
    .setExpirationTime("1h")
    .sign(privateKey);
}

function orderRequest(appCheck: string) {
  return new Request("https://worker.test/v1/orders", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: "Bearer x", "X-Firebase-AppCheck": appCheck },
    body: "{}",
  });
}

describe("App Check enforce when Google keys are unavailable", () => {
  it("returns 503 (not an app-version error) when the JWKS endpoint answers 500", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response("upstream error", { status: 500 }));
    const response = await worker.fetch(orderRequest(await signedToken("k-500")), env as never);
    expect(response.status).toBe(503);
    expect(((await response.json()) as { error: string }).error).not.toContain("نسخة التطبيق");
  });
});
