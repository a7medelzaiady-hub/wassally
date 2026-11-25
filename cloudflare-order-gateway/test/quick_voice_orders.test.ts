import { describe, expect, it } from "vitest";
import {
  QuickRuleError,
  newQuickOrder,
  quickCustomerVoice,
  quickDeliveredPatch,
  resolveQuickSettings,
  validateQuickStores,
  validateQuickVoice,
} from "../src/quick_orders";
import { isOwnQuickVoice, quickRequestFolder, detectAudioContent } from "../src/index";

const CLOUD = "g3n5pdfz";
const makeUrl = (folder: string, name = "clip") =>
  `https://res.cloudinary.com/${CLOUD}/video/upload/v1732270000/${folder}/${name}.m4a`;

describe("quick customer voice", () => {
  it("only accepts one owned Cloudinary audio URL in the voice subfolder", async () => {
    const folder = (await quickRequestFolder("cust1")) + "/voice";
    const ownUrl = makeUrl(folder);
    const own = (url: string) => isOwnQuickVoice(url, folder, CLOUD);
    expect(own(ownUrl)).toBe(true);
    expect(validateQuickVoice(ownUrl, own)).toBe(ownUrl);
    expect(validateQuickVoice(undefined, own)).toBe("");
    expect(own(makeUrl((await quickRequestFolder("cust2")) + "/voice"))).toBe(false);
    expect(own(ownUrl.replace(CLOUD, "other"))).toBe(false);
    expect(own(ownUrl.replace("/video/upload/", "/image/upload/"))).toBe(false);
    expect(own("https://evil.example/video/upload/" + folder + "/clip.m4a")).toBe(false);
    expect(own(ownUrl.replace("/voice/", "/public/"))).toBe(false);
    for (const invalid of [makeUrl((await quickRequestFolder("cust2")) + "/voice"), "", "https://example.com/a", 44]) {
      if (invalid === "") continue; // no voice is allowed
      expect(() => validateQuickVoice(invalid, own)).toThrow(QuickRuleError);
    }
  });

  it("supports a voice-only order and removes its Firestore URL on PIN delivery", async () => {
    const folder = (await quickRequestFolder("cust1")) + "/voice";
    const voice = makeUrl(folder);
    const stores = validateQuickStores(undefined, true);
    const order = newQuickOrder({
      uid: "cust1", customerFirstName: "Ahmed", area: "الحي",
      notes: "", stores, customerVoiceUrl: voice,
      settings: resolveQuickSettings(null),
    });
    expect(order.customerVoiceUrl).toBe(voice);
    expect(quickCustomerVoice(order)).toBe(voice);
    const delivered = quickDeliveredPatch(
      { ...order, totals: { serviceFee: 500, due: 1800 } },
      "cour1", new Date(),
    );
    expect(delivered.customerVoiceUrl).toBe("");
    expect(quickCustomerVoice({ ...order, ...delivered })).toBe("");
    expect(newQuickOrder({
      uid: "cust1", customerFirstName: "Ahmed", area: "الحي", notes: "",
      stores: [{ name: "", items: "لبن" }], settings: resolveQuickSettings(null),
    }).customerVoiceUrl).toBe("");
  });

  it("validates the voice file content by signature, not uploaded extension", () => {
    const mp4 = new Uint8Array([0, 0, 0, 16, 102, 116, 121, 112, 77, 52, 65, 32]);
    expect(detectAudioContent(mp4)?.format).toBe("m4a");
    expect(detectAudioContent(new Uint8Array([1, 2, 3, 4]))).toBe(null);
  });
});
