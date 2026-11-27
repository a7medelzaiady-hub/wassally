import { afterEach, describe, expect, it, vi } from "vitest";
import { courierTopicMessage, deliverClaimedOrderPush, notifyOrderParticipant, quickTopicMessage } from "../src/index";

const env = { FIREBASE_PROJECT_ID: "test-project" } as never;
const documentName = "projects/test-project/databases/(default)/documents/orders/order_1/pushEvents/created";

afterEach(() => {
  vi.unstubAllGlobals();
});

function stubFirestoreCommit() {
  let marker: "none" | "pending" | "sent" = "none";
  const bodies: any[] = [];
  const fetchMock = vi.fn(async (_url: string, init: RequestInit) => {
    const body = JSON.parse(String(init.body));
    bodies.push(body);
    const write = body.writes[0];
    if (write.currentDocument?.exists === false) {
      if (marker !== "none") {
        return new Response(JSON.stringify({ error: { status: "ALREADY_EXISTS" } }), { status: 409 });
      }
      marker = "pending";
    } else if (write.delete) {
      marker = "none";
    } else if (write.updateMask) {
      marker = "sent";
    }
    return new Response("{}", { status: 200 });
  });
  vi.stubGlobal("fetch", fetchMock);
  return { bodies, getMarker: () => marker, fetchMock };
}

describe("push delivery claim lifecycle", () => {
  it("marks sent only after one successful FCM send and suppresses duplicates", async () => {
    const store = stubFirestoreCommit();
    const fail = vi.fn().mockResolvedValue(false);
    const succeed = vi.fn().mockResolvedValue(true);
    const send = [fail, succeed];
    expect(await deliverClaimedOrderPush(env, "bearer", "orders/order_1/pushEvents/created", "created", send)).toBe(true);
    expect(store.getMarker()).toBe("sent");
    expect(store.bodies[0].writes[0].update.fields.state.stringValue).toBe("pending");
    expect(store.bodies[1].writes[0].update.fields.state.stringValue).toBe("sent");
    expect(store.bodies[1].writes[0].updateMask.fieldPaths).toEqual(["state"]);
    expect(store.bodies[1].writes[0].update.name).toBe(documentName);
    expect(await deliverClaimedOrderPush(env, "bearer", "orders/order_1/pushEvents/created", "created", send)).toBe(false);
    expect(succeed).toHaveBeenCalledTimes(1);
  });

  it("releases an all-failed marker so the same event can be retried", async () => {
    const store = stubFirestoreCommit();
    await expect(deliverClaimedOrderPush(env, "bearer", "orders/order_1/pushEvents/created", "created", [
      () => Promise.reject(new Error("timeout")),
      async () => false,
    ])).rejects.toThrow();
    expect(store.getMarker()).toBe("none");
    expect(store.bodies[1].writes[0].delete).toBe(documentName);
    expect(await deliverClaimedOrderPush(env, "bearer", "orders/order_1/pushEvents/created", "created", [
      async () => true,
    ])).toBe(true);
    expect(store.getMarker()).toBe("sent");
  });

  it("retains a claim if confirmation fails after FCM accepted a push, preventing duplicates", async () => {
    let claimCount = 0;
    const fetchMock = vi.fn(async () => {
      claimCount += 1;
      if (claimCount === 1) return new Response("{}", { status: 200 });
      return new Response("service unavailable", { status: 503 });
    });
    vi.stubGlobal("fetch", fetchMock);
    await expect(deliverClaimedOrderPush(env, "bearer", "orders/order_1/pushEvents/created", "created", [
      async () => true,
    ])).rejects.toThrow();
    expect(fetchMock).toHaveBeenCalledTimes(2); // no unsafe deletion
  });
});

describe("recipient push cleanup and timeout budgets", () => {
  it("prunes a 404/UNREGISTERED token via Firestore transform, without an extra read", async () => {
    const fetchMock = vi.fn(async (url: string, init: RequestInit) => {
      if (url.includes("/documents/users/")) {
        return new Response(JSON.stringify({ fields: {
          fcmTokens: { arrayValue: { values: [{ stringValue: "dead-fcm-token" }] } },
        } }));
      }
      if (url.includes("messages:send")) {
        expect(init.signal).toBeDefined();
        return new Response(JSON.stringify({ error: { details: [{ errorCode: "UNREGISTERED" }] } }), { status: 404 });
      }
      if (url.endsWith(":commit")) {
        const write = JSON.parse(String(init.body)).writes[0];
        expect(write.transform.document).toContain("/users/recipient_1");
        expect(write.transform.fieldTransforms[0].removeAllFromArray.values)
          .toEqual([{ stringValue: "dead-fcm-token" }]);
        return new Response("{}", { status: 200 });
      }
      throw new Error("unexpected URL: " + url);
    });
    vi.stubGlobal("fetch", fetchMock);
    const sent = await notifyOrderParticipant(env, "bearer", "recipient_1", "order_1", "order_update", "Order updated");
    expect(sent).toBe(false);
    expect(fetchMock).toHaveBeenCalledTimes(3); // one read, one FCM request, one transform write
  });

  it("returns success for mixed accepted and invalid tokens", async () => {
    const fetchMock = vi.fn(async (url: string, init: RequestInit) => {
      if (url.includes("/documents/users/")) {
        return new Response(JSON.stringify({ fields: { fcmTokens: { arrayValue: { values: [
          { stringValue: "valid" }, { stringValue: "dead" },
        ] } } } }));
      }
      if (url.includes("messages:send")) {
        const token = JSON.parse(String(init.body)).message.token;
        return token === "valid" ? new Response("{}", { status: 200 }) :
          new Response("{}", { status: 404 });
      }
      return new Response("{}", { status: 200 });
    });
    vi.stubGlobal("fetch", fetchMock);
    expect(await notifyOrderParticipant(env, "bearer", "recipient_1", "order_1", "order_update", "Update")).toBe(true);
    expect(fetchMock).toHaveBeenCalledTimes(4);
  });
});

describe("courier topic notification TTL", () => {
  it("allows 30 minutes for ordinary and quick courier alerts", () => {
    for (const message of [courierTopicMessage("Store"), quickTopicMessage(), quickTopicMessage(true)]) {
      expect(message.message.android.priority).toBe("HIGH");
      expect(message.message.android.ttl).toBe("1800s");
    }
  });
});
