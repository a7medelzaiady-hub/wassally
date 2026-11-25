import { describe, expect, it } from "vitest";
import {
  QUICK_MAX_CUSTOMER_IMAGES,
  QuickRuleError,
  newQuickOrder,
  quickCustomerImages,
  quickDeliveredPatch,
  resolveQuickSettings,
  validateQuickImages,
  validateQuickStores,
} from "../src/quick_orders";
import { isOwnQuickImage, quickRequestFolder } from "../src/index";

const CLOUD = "g3n5pdfz";

async function ownUrl(uid: string, id = "a1b2c3"): Promise<string> {
  return `https://res.cloudinary.com/${CLOUD}/image/upload/v1/${await quickRequestFolder(uid)}/${id}.jpg`;
}

describe("«صوّر طلبك» — صور الطلب السريع", () => {
  it("مجلد الصور جوه مجلد طلبات العميل الخاصة (حذف الحساب بيمسحه)", async () => {
    const folder = await quickRequestFolder("cust1");
    expect(folder).toMatch(/^special_requests\/[0-9a-f]{64}\/quick$/);
    expect(await quickRequestFolder("cust2")).not.toBe(folder);
  });

  it("بيقبل صور العميل نفسه بس ومن نفس الحساب على Cloudinary", async () => {
    const folder = await quickRequestFolder("cust1");
    expect(isOwnQuickImage(await ownUrl("cust1"), folder, CLOUD)).toBe(true);
    expect(isOwnQuickImage(await ownUrl("cust2"), folder, CLOUD)).toBe(false);
    expect(isOwnQuickImage((await ownUrl("cust1")).replace(CLOUD, "other"), folder, CLOUD)).toBe(false);
    expect(isOwnQuickImage("https://evil.example/image/upload/x.jpg", folder, CLOUD)).toBe(false);
  });

  it("لحد 3 صور، من غير تكرار، وكلها صالحة", async () => {
    const folder = await quickRequestFolder("cust1");
    const ok = (url: string) => isOwnQuickImage(url, folder, CLOUD);
    const urls = [await ownUrl("cust1", "a"), await ownUrl("cust1", "b"), await ownUrl("cust1", "c")];
    expect(validateQuickImages(urls, ok)).toEqual(urls);
    expect(validateQuickImages(undefined, ok)).toEqual([]);
    expect(() => validateQuickImages([...urls, await ownUrl("cust1", "d")], ok)).toThrow(QuickRuleError);
    expect(() => validateQuickImages([urls[0], urls[0]], ok)).toThrow(QuickRuleError);
    expect(() => validateQuickImages([await ownUrl("cust2")], ok)).toThrow(QuickRuleError);
    expect(QUICK_MAX_CUSTOMER_IMAGES).toBe(3);
  });

  it("صورة بس من غير كتابة = طلب صالح؛ من غير صور الكتابة لسه مطلوبة", () => {
    expect(validateQuickStores(undefined, true)).toEqual([{ name: "", items: "" }]);
    expect(validateQuickStores([{ name: "", items: "" }], true)).toEqual([{ name: "", items: "" }]);
    expect(() => validateQuickStores([{ name: "", items: "" }], false)).toThrow(QuickRuleError);
    expect(validateQuickStores([{ name: "بقالة", items: "لبن" }], true))
      .toEqual([{ name: "بقالة", items: "لبن" }]);
  });

  it("الطلب بيحفظ الصور، والتسليم بيشيل مراجعها", async () => {
    const urls = [await ownUrl("cust1")];
    const order = newQuickOrder({
      uid: "cust1",
      customerFirstName: "أحمد",
      area: "بيلا",
      notes: "",
      stores: [{ name: "", items: "" }],
      settings: resolveQuickSettings(null),
      customerImages: urls,
    });
    expect(order.customerImages).toEqual(urls);
    expect(quickCustomerImages(order)).toEqual(urls);
    const patch = quickDeliveredPatch({ ...order, totals: { serviceFee: 500, due: 1000 } }, "courier1", new Date());
    expect(patch.customerImages).toEqual([]);
    expect(quickCustomerImages({ ...order, ...patch })).toEqual([]);
  });

  it("طلب قديم من غير صور يفضل شغال", () => {
    const order = newQuickOrder({
      uid: "cust1",
      customerFirstName: "أحمد",
      area: "بيلا",
      notes: "",
      stores: [{ name: "", items: "لبن" }],
      settings: resolveQuickSettings(null),
    });
    expect(order.customerImages).toEqual([]);
    expect(quickCustomerImages({})).toEqual([]);
  });
});
