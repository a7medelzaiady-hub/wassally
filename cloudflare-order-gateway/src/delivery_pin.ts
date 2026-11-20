/** Secure 4-digit delivery PIN primitives. Never expose a PIN or its digest in courier-readable order data. */
const encoder = new TextEncoder();

export function generateDeliveryPin(): string {
  const bytes = new Uint32Array(1);
  // Rejection sampling avoids modulo bias.
  const limit = Math.floor(0x100000000 / 10000) * 10000;
  let value: number;
  do {
    crypto.getRandomValues(bytes);
    value = bytes[0];
  } while (value >= limit);
  return String(value % 10000).padStart(4, "0");
}

export function isDeliveryPin(value: unknown): value is string {
  return typeof value === "string" && /^[0-9]{4}$/.test(value);
}

/** Per-order random salt + server-only pepper; do not store pepper in Firestore. */
export async function hashDeliveryPin(
  pin: string,
  orderId: string,
  salt: string,
  pepper: string,
): Promise<string> {
  if (!isDeliveryPin(pin) || !orderId || !salt || !pepper) {
    throw new Error("Invalid PIN hash input");
  }
  const key = await crypto.subtle.importKey(
    "raw", encoder.encode(pepper), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, encoder.encode(
    JSON.stringify([orderId, salt, pin]),
  ));
  return Array.from(new Uint8Array(mac), (b) => b.toString(16).padStart(2, "0")).join("");
}

export function equalHexDigest(left: string, right: string): boolean {
  if (!/^[0-9a-f]{64}$/.test(left) || !/^[0-9a-f]{64}$/.test(right)) return false;
  let diff = 0;
  for (let i = 0; i < 64; i++) diff |= left.charCodeAt(i) ^ right.charCodeAt(i);
  return diff === 0;
}

/**
 * Persist attempts per order in a server-only Firestore document and update with
 * a precondition/transaction. A process-local counter is NOT sufficient on Workers.
 */
export const DELIVERY_PIN_MAX_ATTEMPTS = 5;

export function canAttemptDeliveryPin(
  attempts: number,
  locked: boolean,
): boolean {
  return Number.isSafeInteger(attempts) &&
    attempts >= 0 &&
    attempts < DELIVERY_PIN_MAX_ATTEMPTS &&
    !locked;
}

export function nextDeliveryPinFailure(attempts: number): {
  attempts: number;
  locked: boolean;
} {
  if (!canAttemptDeliveryPin(attempts, false)) {
    return { attempts: Math.max(DELIVERY_PIN_MAX_ATTEMPTS, attempts), locked: true };
  }
  const next = attempts + 1;
  return { attempts: next, locked: next >= DELIVERY_PIN_MAX_ATTEMPTS };
}

/**
 * Pure verification decision. Caller MUST persist the returned failure count
 * or successful consumption atomically using the Firestore updateTime precondition.
 * Never return the PIN, hash, or salt to a courier.
 */
export type DeliveryPinDecision =
  | { outcome: "accepted"; attempts: number; consumed: true; locked: false }
  | { outcome: "rejected"; attempts: number; consumed: false; locked: boolean }
  | { outcome: "unavailable"; attempts: number; consumed: boolean; locked: boolean };

export function decideDeliveryPinVerification(
  submittedDigest: string,
  storedDigest: string,
  attempts: number,
  locked: boolean,
  consumed: boolean,
): DeliveryPinDecision {
  if (!Number.isSafeInteger(attempts) || attempts < 0 || typeof locked !== "boolean" ||
      typeof consumed !== "boolean") {
    return { outcome: "unavailable", attempts: DELIVERY_PIN_MAX_ATTEMPTS, consumed: true, locked: true };
  }
  if (consumed || !canAttemptDeliveryPin(attempts, locked)) {
    return { outcome: "unavailable", attempts, consumed, locked };
  }
  if (equalHexDigest(submittedDigest, storedDigest)) {
    return { outcome: "accepted", attempts, consumed: true, locked: false };
  }
  const failure = nextDeliveryPinFailure(attempts);
  return { outcome: "rejected", attempts: failure.attempts, consumed: false, locked: failure.locked };
}
