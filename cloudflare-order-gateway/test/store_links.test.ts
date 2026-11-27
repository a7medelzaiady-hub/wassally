import { describe, expect, it, vi } from "vitest";

vi.mock("jose", () => ({
  createRemoteJWKSet: () => () => ({}),
  jwtVerify: async () => ({ payload: {} }),
  importPKCS8: async () => ({}),
  SignJWT: class {},
}));

import worker from "../src/index";
import {
  appIntentUrl, assetLinksResponse, playStoreUrl, storeIdFromPath, storeLinkResponse,
} from "../src/store_links";

const env = { FIREBASE_PROJECT_ID: "wasally-test" } as any;
const FP = Array.from({ length: 32 }, () => "AB").join(":");

describe("store share links", () => {
  it("parses only safe store ids from /s/<id>", () => {
    expect(storeIdFromPath("/s/abc_123-X")).toBe("abc_123-X");
    expect(storeIdFromPath("/s/abc/")).toBe("abc");
    expect(storeIdFromPath("/s/")).toBeNull();
    expect(storeIdFromPath("/s/a/b")).toBeNull();
    expect(storeIdFromPath("/s/%3Cscript%3E")).toBeNull();
    expect(storeIdFromPath("/s/%E0%A4%A")).toBeNull();
    expect(storeIdFromPath("/x/abc")).toBeNull();
  });

  it("falls back to Google Play with the store in the referrer", () => {
    const url = new URL(playStoreUrl("shop1"));
    expect(url.hostname).toBe("play.google.com");
    expect(url.searchParams.get("id")).toBe("com.wassally.app");
    expect(url.searchParams.get("referrer")).toBe("utm_source=share&utm_content=store_shop1");
    const intent = appIntentUrl("shop1");
    expect(intent).toContain("intent://open/s/shop1#Intent;scheme=wasally;package=com.wassally.app;");
    expect(intent).toContain("S.browser_fallback_url=" + encodeURIComponent(playStoreUrl("shop1")));
  });

  it("serves a static page with no store data and a strict CSP", async () => {
    const res = storeLinkResponse("shop1");
    expect(res.headers.get("content-type")).toContain("text/html");
    expect(res.headers.get("content-security-policy")).toContain("default-src 'none'");
    const html = await res.text();
    expect(html).toContain("افتح في التطبيق");
    expect(html).toContain("play.google.com");
  });

  it("asset links list only valid fingerprints (empty list when none)", async () => {
    expect(await assetLinksResponse(undefined).json()).toEqual([]);
    expect(await assetLinksResponse("bad, 12:34").json()).toEqual([]);
    const body = await assetLinksResponse(` ${FP.toLowerCase()} , bad`).json() as any[];
    expect(body[0].target.package_name).toBe("com.wassally.app");
    expect(body[0].target.sha256_cert_fingerprints).toEqual([FP]);
    expect(body[0].relation).toEqual(["delegate_permission/common.handle_all_urls"]);
  });

  it("worker routes both before CORS checks, without Firestore", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch");
    const page = await worker.fetch(new Request("https://w.example/s/shop1"), env);
    expect(page.status).toBe(200);
    expect(await page.text()).toContain("intent://open/s/shop1");
    const links = await worker.fetch(
      new Request("https://w.example/.well-known/assetlinks.json"),
      { ...env, ANDROID_SHA256_CERT_FINGERPRINTS: FP },
    );
    expect(((await links.json()) as any[])[0].target.sha256_cert_fingerprints).toEqual([FP]);
    expect(fetchSpy).not.toHaveBeenCalled();
    fetchSpy.mockRestore();
  });
});
