import { describe, expect, it } from "vitest";
import { anonymizeDeliveryIssue, calculateDiscount, catalogPriceMatches, cloudinarySignature, detectImageContent, effectiveCatalogPrice, isUploadSizeAllowed, isUploadRequestLengthAllowed, firstName, isRecentAuthTime, isGoogleSignIn, isCustomerRestricted, sanitizePublicOrder, isUploadRateLimited, CUSTOMER_ORDER_DELETE_FIELD_PATHS, PRIVATE_ORDER_FIELDS, shouldRequeueCourierOrder, courierAvailableFeedData, sanitizeCourierFeed, isAuthTimeAfterValidSince, canUploadSpecialRequestImage, cloudinarySpecialRequestFolder, isCloudinaryImageUrl } from "../src/index";

describe("customer restriction fail-closed behavior", () => {
  const now = Date.UTC(2026, 10, 17);

  it("allows an account with no restriction document", () => {
    expect(isCustomerRestricted(null, now)).toBe(false);
  });
it("fails closed when a restriction document exists but is empty", () => {
    expect(isCustomerRestricted({}, now)).toBe(true);
  });

  it("allows only an explicitly deactivated restriction", () => {
    expect(isCustomerRestricted({ active: false }, now)).toBe(false);
    expect(isCustomerRestricted({ active: false, expiresAt: new Date(now + 60_000) }, now)).toBe(false);
  });

  it("blocks active restrictions until a valid expiry has passed", () => {
    expect(isCustomerRestricted({ active: true, expiresAt: new Date(now + 1) }, now)).toBe(true);
    expect(isCustomerRestricted({ active: true, expiresAt: new Date(now - 1) }, now)).toBe(false);
  });

  it("fails closed for missing, malformed, or invalid expiry data", () => {
    expect(isCustomerRestricted({ active: true }, now)).toBe(true);
    expect(isCustomerRestricted({ active: true, expiresAt: "yesterday" }, now)).toBe(true);
    expect(isCustomerRestricted({ active: true, expiresAt: new Date(Number.NaN) }, now)).toBe(true);
    expect(isCustomerRestricted({ active: true, expiresAt: null }, now)).toBe(true);
    expect(isCustomerRestricted({ expiresAt: null }, now)).toBe(true);
  });

  it("matches the expiry alternative even if the active flag is missing", () => {
    expect(isCustomerRestricted({ active: null, expiresAt: new Date(now - 1) }, now)).toBe(false);
    expect(isCustomerRestricted({ active: null }, now)).toBe(true);
  });
});

describe("trusted catalog pricing", () => {
  it("calculates percentage discounts using the same floor-to-piastre rule as the app", () => {
    expect(calculateDiscount(123.45, 10)).toBe(12.34);
    expect(calculateDiscount(50, 50)).toBe(25);
    expect(calculateDiscount(20, 0)).toBe(0);
  });

  it("uses client prices only to detect a stale cart, never as the saved price", () => {
    expect(catalogPriceMatches(17.5, 17.5)).toBe(true);
    expect(catalogPriceMatches(17, 17.5)).toBe(false);
    expect(catalogPriceMatches(Number.NaN, 17.5)).toBe(false);
  });

  it("uses the catalog price, not a client-supplied amount", () => {
    expect(effectiveCatalogPrice({ price: 17.5 })).toBe(17.5);
  });

  it("keeps an active offer and restores oldPrice after expiry", () => {
    const now = Date.UTC(2026, 10, 16);
    const active = { price: 12, oldPrice: 15, offerEndsAt: new Date(now + 60_000) };
    const expired = { price: 12, oldPrice: 15, offerEndsAt: new Date(now - 1) };
    expect(effectiveCatalogPrice(active, now)).toBe(12);
    expect(effectiveCatalogPrice(expired, now)).toBe(15);
  });

  it("ignores malformed string oldPrice values", () => {
    const now = Date.UTC(2026, 10, 16);
    expect(effectiveCatalogPrice({
      price: 12,
      oldPrice: "15",
      offerEndsAt: new Date(now - 1),
    }, now)).toBe(12);
  });

  it("rejects invalid catalog prices", () => {
    expect(() => effectiveCatalogPrice({ price: 0 })).toThrow();
    expect(() => effectiveCatalogPrice({ price: 20001 })).toThrow();
  });
});


describe("courier notification payload", () => {
  it("sends only a minimal new-order notice to the server-controlled couriers topic", async () => {
    const { courierTopicMessage } = await import("../src/index");
    const payload = courierTopicMessage("abcde_1234567890123456", "متجر تجريبي");
    expect(payload.message.topic).toBe("couriers");
    expect(payload.message.data).toEqual({
      type: "available_order",
      orderId: "abcde_1234567890123456",
    });
    expect(payload.message.notification.title).toContain("#ABCDE");
    expect(payload.message.notification.body).toContain("متجر تجريبي");
    expect(payload.message.android.ttl).toBe("300s");
    expect(JSON.stringify(payload)).not.toContain("phone");
    expect(JSON.stringify(payload)).not.toContain("address");
  });
});


describe("customer name normalization", () => {
  it("uses the first whitespace-separated name consistently", () => {
    expect(firstName("  Ahmed   Mohamed  ")).toBe("Ahmed");
    expect(firstName("أحمد محمد")).toBe("أحمد");
    expect(firstName("Single")).toBe("Single");
    expect(firstName("   ")).toBe("");
    expect(firstName(null)).toBe("");
  });
});


describe("server-side image content validation", () => {
  it("enforces the five-megabyte upload boundary", () => {
    expect(isUploadSizeAllowed(1)).toBe(true);
    expect(isUploadSizeAllowed(5 * 1024 * 1024)).toBe(true);
    expect(isUploadSizeAllowed(5 * 1024 * 1024 + 1)).toBe(false);
    expect(isUploadSizeAllowed(0)).toBe(false);
    expect(isUploadSizeAllowed(Number.NaN)).toBe(false);
  });

  it("requires a bounded Content-Length before parsing multipart bodies", () => {
    expect(isUploadRequestLengthAllowed("1")).toBe(true);
    expect(isUploadRequestLengthAllowed(String(5 * 1024 * 1024 + 64 * 1024))).toBe(true);
    expect(isUploadRequestLengthAllowed(null)).toBe(false);
    expect(isUploadRequestLengthAllowed("")).toBe(false);
    expect(isUploadRequestLengthAllowed("0")).toBe(false);
    expect(isUploadRequestLengthAllowed("-1")).toBe(false);
    expect(isUploadRequestLengthAllowed("1.5")).toBe(false);
    expect(isUploadRequestLengthAllowed("5e6")).toBe(false);
    expect(isUploadRequestLengthAllowed(String(5 * 1024 * 1024 + 64 * 1024 + 1))).toBe(false);
    expect(isUploadRequestLengthAllowed("999999999999999999999")).toBe(false);
  });

  it("accepts JPEG, PNG, and WEBP signatures", () => {
    expect(detectImageContent(new Uint8Array([0xff, 0xd8, 0xff, 0x00]))).toEqual({
      format: "jpg",
      mime: "image/jpeg",
    });
    expect(detectImageContent(new Uint8Array([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
    ]))).toEqual({
      format: "png",
      mime: "image/png",
    });
    expect(detectImageContent(new Uint8Array([
      0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00,
      0x57, 0x45, 0x42, 0x50,
    ]))).toEqual({
      format: "webp",
      mime: "image/webp",
    });
  });

  it("rejects extensions or MIME spoofing without a supported file signature", () => {
    expect(detectImageContent(new TextEncoder().encode("<svg></svg>"))).toBeNull();
    expect(detectImageContent(new Uint8Array([0x25, 0x50, 0x44, 0x46]))).toBeNull();
    expect(detectImageContent(new Uint8Array([]))).toBeNull();
  });
});

describe("Cloudinary upload signatures", () => {
  it("signs a canonical sorted parameter set and changes when the folder changes", async () => {
    const params = {
      timestamp: "1794850000",
      folder: "stores/store_1",
      public_id: "unique-image-id",
      allowed_formats: "jpg,jpeg,png,webp",
      overwrite: "false",
      unique_filename: "true",
      use_filename: "false",
    };
    const first = await cloudinarySignature(params, "test-secret");
    const same = await cloudinarySignature({
      use_filename: "false",
      folder: "stores/store_1",
      public_id: "unique-image-id",
      overwrite: "false",
      timestamp: "1794850000",
      unique_filename: "true",
      allowed_formats: "jpg,jpeg,png,webp",
    }, "test-secret");
    const otherFolder = await cloudinarySignature(
      { ...params, folder: "stores/store_2" },
      "test-secret",
    );
    expect(first).toMatch(/^[a-f0-9]{40}$/);
    expect(same).toBe(first);
    expect(otherFolder).not.toBe(first);
  });
});


describe("account deletion privacy cleanup", () => {
  it("anonymizes courier identity and free-text notes in delivery issues", () => {
    expect(anonymizeDeliveryIssue({
      courierId: "user-1", customerId: "customer-2", createdBy: "user-1",
      note: "Personal contact details", status: "open",
    }, "user-1")).toEqual({
      courierId: "deleted", createdBy: "deleted", note: "", adminDecision: "",
    });
  });

  it("anonymizes customer identity and free-text notes in delivery issues", () => {
    expect(anonymizeDeliveryIssue({
      courierId: "courier-2", customerId: "user-1", createdBy: "courier-2",
      note: "Personal contact details", adminDecision: "Customer phone: 01000000000",
      status: "open",
    }, "user-1")).toEqual({
      customerId: "deleted", note: "", adminDecision: "",
    });
  });

  it("anonymizes the creator UID when the customer opened the issue", () => {
    expect(anonymizeDeliveryIssue({
      courierId: "courier-2", customerId: "user-1", createdBy: "user-1",
      note: "Private address", status: "open",
    }, "user-1")).toEqual({
      customerId: "deleted", createdBy: "deleted", note: "", adminDecision: "",
    });
  });

  it("removes a deleted administrator from decision metadata and free text", () => {
    expect(anonymizeDeliveryIssue({
      courierId: "courier-2", customerId: "customer-2",
      createdBy: "courier-2", updatedBy: "user-1",
      adminDecision: "Personal details in decision", note: "Courier note",
    }, "user-1")).toEqual({
      updatedBy: "deleted", adminDecision: "",
    });
  });

  it("does not modify an issue unrelated to the deleted account", () => {
    expect(anonymizeDeliveryIssue({
      courierId: "courier-2", customerId: "customer-2", note: "keep",
    }, "user-1")).toEqual({});
  });
});

describe("account deletion authentication freshness", () => {
  it("accepts only authentication performed within the last five minutes", () => {
    const now = 1_800_000_000;
    expect(isRecentAuthTime(now, now)).toBe(true);
    expect(isRecentAuthTime(now - 300, now)).toBe(true);
    expect(isRecentAuthTime(now - 301, now)).toBe(false);
    expect(isRecentAuthTime(now + 61, now)).toBe(false);
    expect(isRecentAuthTime(Number.NaN, now)).toBe(false);
    expect(isRecentAuthTime(0, now)).toBe(false);
  });
});


describe("gateway Google-only authentication", () => {
  it("accepts Firebase ID tokens authenticated with Google", () => {
    expect(isGoogleSignIn({ firebase: { sign_in_provider: "google.com" } })).toBe(true);
  });

  it("rejects password, anonymous, missing, and malformed provider claims", () => {
    expect(isGoogleSignIn({ firebase: { sign_in_provider: "password" } })).toBe(false);
    expect(isGoogleSignIn({ firebase: { sign_in_provider: "anonymous" } })).toBe(false);
    expect(isGoogleSignIn({})).toBe(false);
    expect(isGoogleSignIn({ firebase: null })).toBe(false);
    expect(isGoogleSignIn({ firebase: "google.com" })).toBe(false);
  });
});


describe("public order contact sanitization", () => {
  it("removes legacy contact fields while preserving order and delivery data", () => {
    expect(sanitizePublicOrder({
      userId: "customer-1",
      customerName: "Ali",
      userName: "Ali Full",
      userEmail: "ali@example.test",
      phone: "01000000000",
      address: "Private address",
      courierNotes: "Call me",
      contact: { phone: "01000000000" },
      items: [{ name: "Bread", qty: 1 }],
      notes: "Leave at door",
      status: "preparing",
      total: 125,
    })).toEqual({
      userId: "customer-1",
      customerName: "Ali",
      items: [{ name: "Bread", qty: 1 }],
      notes: "Leave at door",
      status: "preparing",
      total: 125,
    });
  });
});


describe("image upload rate limiting", () => {
  it("uses the verified UID as the limiter key", async () => {
    let receivedKey = "";
    const limiter = {
      limit: async ({ key }: { key: string }) => {
        receivedKey = key;
        return { success: true };
      },
    };
    await expect(isUploadRateLimited(limiter, "user-123")).resolves.toBe(false);
    expect(receivedKey).toBe("user-123");
  });

  it("rejects uploads when Cloudflare reports the per-user limit exceeded", async () => {
    const limiter = { limit: async (_: { key: string }) => ({ success: false }) };
    await expect(isUploadRateLimited(limiter, "user-123")).resolves.toBe(true);
  });
});


describe("account deletion order privacy mask", () => {
  it("clears every legacy private field from customer order documents", () => {
    for (const field of PRIVATE_ORDER_FIELDS) {
      expect(CUSTOMER_ORDER_DELETE_FIELD_PATHS).toContain(field);
    }
    expect(CUSTOMER_ORDER_DELETE_FIELD_PATHS).toContain("userId");
    expect(CUSTOMER_ORDER_DELETE_FIELD_PATHS).toContain("userDeleted");
    expect(CUSTOMER_ORDER_DELETE_FIELD_PATHS).toContain("customerName");
    expect(CUSTOMER_ORDER_DELETE_FIELD_PATHS).toContain("notes");
  });
});


describe("courier account deletion order recovery", () => {
  it("requeues preparing and in-transit orders only when no delivery decision is pending", () => {
    expect(shouldRequeueCourierOrder({ status: "preparing" })).toBe(true);
    expect(shouldRequeueCourierOrder({ status: "on_the_way" })).toBe(true);
    expect(shouldRequeueCourierOrder({
      status: "on_the_way", activeDeliveryIssueId: "issue-1",
    })).toBe(false);
    expect(shouldRequeueCourierOrder({
      status: "on_the_way", customerDeliveryReportedAt: new Date(),
    })).toBe(false);
    expect(shouldRequeueCourierOrder({ status: "delivered" })).toBe(false);
  });

  it("builds a courier feed without customer identity or contact fields", () => {
    expect(courierAvailableFeedData({
      storeId: "store-1",
      storeName: "Market",
      area: "Area",
      items: [{ name: "Bread", qty: 1 }],
      subtotal: 100,
      deliveryFee: 20,
      total: 120,
      createdAt: new Date(0),
      userId: "customer-1",
      customerName: "Ali",
      phone: "01000000000",
      address: "Private address",
      courierNotes: "Private note",
    })).toEqual({
      storeId: "store-1",
      storeName: "Market",
      area: "Area",
      items: [{ name: "Bread", qty: 1 }],
      subtotal: 100,
      deliveryFee: 20,
      discount: 0,
      total: 120,
      status: "preparing",
      createdAt: new Date(0),
    });
  });
});


describe("courier feed privacy sanitization", () => {
  it("keeps only the public allow-listed fields when updating legacy feeds", () => {
    expect(sanitizeCourierFeed({
      storeId: "store-1",
      storeName: "Market",
      area: "Area",
      items: [],
      subtotal: 100,
      deliveryFee: 20,
      total: 120,
      status: "preparing",
      createdAt: new Date(0),
      userId: "customer-1",
      customerName: "Ali",
      phone: "01000000000",
      address: "Private address",
      courierNotes: "Private note",
      adminNote: "internal",
    })).toEqual({
      storeId: "store-1",
      storeName: "Market",
      area: "Area",
      items: [],
      subtotal: 100,
      deliveryFee: 20,
      total: 120,
      status: "preparing",
      createdAt: new Date(0),
    });
  });
});


describe("Firebase token revocation checks", () => {
  it("rejects tokens issued before the user's validSince boundary", () => {
    expect(isAuthTimeAfterValidSince(2_000, 1_999)).toBe(true);
    expect(isAuthTimeAfterValidSince(2_000, 2_000)).toBe(true);
    expect(isAuthTimeAfterValidSince(1_999, 2_000)).toBe(false);
    expect(isAuthTimeAfterValidSince(Number.NaN, 2_000)).toBe(false);
    expect(isAuthTimeAfterValidSince(2_000, Number.NaN)).toBe(false);
  });
});


describe("customer special-request image uploads", () => {
  it("allows uploads only for a valid store that is active", () => {
    expect(canUploadSpecialRequestImage("store-1", { active: true })).toBe(true);
    expect(canUploadSpecialRequestImage("store-1", { active: false })).toBe(false);
    expect(canUploadSpecialRequestImage("store-1", null)).toBe(false);
    expect(canUploadSpecialRequestImage("../other", { active: true })).toBe(false);
    expect(canUploadSpecialRequestImage("", { active: true })).toBe(false);
  });

  it("recognizes only secure Cloudinary image delivery URLs", () => {
    expect(isCloudinaryImageUrl("https://res.cloudinary.com/demo/image/upload/special_requests/a.jpg")).toBe(true);
    expect(isCloudinaryImageUrl("http://res.cloudinary.com/demo/image/upload/a.jpg")).toBe(false);
    expect(isCloudinaryImageUrl("https://example.com/image/upload/a.jpg")).toBe(false);
    expect(isCloudinaryImageUrl("not-a-url")).toBe(false);
  });

  it("creates a stable per-user Cloudinary folder without exposing the UID", async () => {
    const folder = await cloudinarySpecialRequestFolder("customer-uid-123");
    expect(folder).toMatch(/^special_requests\/[a-f0-9]{64}$/);
    expect(folder).not.toContain("customer-uid-123");
    await expect(cloudinarySpecialRequestFolder("customer-uid-123")).resolves.toBe(folder);
  });
});
