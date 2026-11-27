import { afterEach, describe, expect, it, vi } from "vitest";
import {
  adminNoticeMessage, courierTopicMessage, quickTopicMessage, notifyOrderParticipant,
} from "../src/index";

afterEach(() => vi.unstubAllGlobals());

describe("FCM Android high-importance order channel", () => {
  it("uses the same channel for courier, quick-courier and admin topics", () => {
    const payloads = [
      courierTopicMessage("محل الاختبار"),
      quickTopicMessage(),
      quickTopicMessage(true),
      adminNoticeMessage("join_request", "courier"),
      adminNoticeMessage("delivery_issue", ""),
    ];
    for (const payload of payloads) {
      expect(payload.message.android.priority).toBe("HIGH");
      expect(payload.message.android.notification.channel_id).toBe("wasally_orders");
      expect(payload.message.android.notification.sound).toBe("default");
    }
  });

  it("adds wasally_orders channel to a directly targeted participant notification", async () => {
    const outgoing: unknown[] = [];
    vi.stubGlobal("fetch", vi.fn(async (url: string, init: RequestInit) => {
      if (url.includes("/documents/users/")) {
        return new Response(JSON.stringify({
          fields: { fcmTokens: { arrayValue: { values: [{ stringValue: "device-1" }] } } },
        }));
      }
      if (url.includes("messages:send")) {
        outgoing.push(JSON.parse(String(init.body)).message);
        return new Response(JSON.stringify({ name: "accepted" }), { status: 200 });
      }
      throw new Error("unexpected HTTP request: " + url);
    }));
    const env = { FIREBASE_PROJECT_ID: "wasally-test" } as never;
    expect(await notifyOrderParticipant(env, "token", "recipient", "order", "order_update", "الحالة اتحدثت")).toBe(true);
    expect(outgoing).toEqual([expect.objectContaining({
      android: expect.objectContaining({
        priority: "HIGH",
        notification: { sound: "default", channel_id: "wasally_orders" },
      }),
    })]);
  });
});
