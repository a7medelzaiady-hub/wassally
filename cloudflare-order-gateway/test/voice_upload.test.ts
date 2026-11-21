import { describe, expect, it } from "vitest";
import {
  cloudinaryPublicIdFromUrl,
  detectAudioContent,
  detectImageContent,
  hasPendingAttachments,
  isCloudinaryVoiceUrl,
} from "../src/index";

describe("special-request voice on Cloudinary", () => {
  it("detects m4a and raw AAC, rejects other bytes", () => {
    const m4a = new Uint8Array([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x4d, 0x34, 0x41, 0x20]);
    expect(detectAudioContent(m4a)).toEqual({ format: "m4a", mime: "audio/mp4" });
    const adts = new Uint8Array([0xff, 0xf1, 0x50, 0x80, 0, 0x1f, 0xfc]);
    expect(detectAudioContent(adts)?.format).toBe("aac");
    expect(detectAudioContent(new Uint8Array([0x3c, 0x68, 0x74, 0x6d, 0x6c, 0, 0, 0, 0, 0, 0, 0]))).toBeNull();
    // ملف صوت مش صورة
    expect(detectImageContent(m4a)).toBeNull();
  });

  it("accepts only special_requests video URLs on Cloudinary", () => {
    expect(isCloudinaryVoiceUrl("https://res.cloudinary.com/demo/video/upload/v17/special_requests/abc/x.m4a")).toBe(true);
    expect(isCloudinaryVoiceUrl("https://res.cloudinary.com/demo/image/upload/special_requests/abc/x.jpg")).toBe(false);
    expect(isCloudinaryVoiceUrl("https://res.cloudinary.com/demo/video/upload/products/x.m4a")).toBe(false);
    expect(isCloudinaryVoiceUrl("https://evil.example/video/upload/special_requests/x.m4a")).toBe(false);
    expect(isCloudinaryVoiceUrl("http://res.cloudinary.com/demo/video/upload/special_requests/x.m4a")).toBe(false);
  });

  it("extracts the public id without version and extension", () => {
    expect(cloudinaryPublicIdFromUrl("https://res.cloudinary.com/demo/video/upload/v17/special_requests/abc/x1.m4a"))
      .toBe("special_requests/abc/x1");
    expect(cloudinaryPublicIdFromUrl("https://res.cloudinary.com/demo/image/upload/special_requests/abc/y.jpg"))
      .toBe("special_requests/abc/y");
  });

  it("a voice link counts as a pending attachment until cleaned", () => {
    expect(hasPendingAttachments({ specialRequest: { voiceUrl: "https://x" } })).toBe(true);
    expect(hasPendingAttachments({ specialRequest: { voiceUrl: "https://x", cleanupStatus: "deleted" } })).toBe(false);
    expect(hasPendingAttachments({ specialRequest: { description: "x" } })).toBe(false);
  });
});
