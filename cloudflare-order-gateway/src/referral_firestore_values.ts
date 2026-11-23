/**
 * Strict decoder for Firestore REST Value objects. Do not treat a malformed
 * document as an empty settings object: referral payouts must fail closed.
 */
export function decodeFirestoreReferralFields(
  fields: Record<string, unknown>,
): Record<string, unknown> {
  function decode(value: unknown, depth: number): unknown {
    if (depth > 8 || !value || typeof value !== "object" || Array.isArray(value)) {
      throw new Error("invalid Firestore referral value");
    }
    const v = value as Record<string, unknown>;
    const keys = Object.keys(v);
    if (keys.length !== 1) throw new Error("ambiguous Firestore value");
    if ("stringValue" in v && typeof v.stringValue === "string") return v.stringValue;
    if ("booleanValue" in v && typeof v.booleanValue === "boolean") return v.booleanValue;
    if ("integerValue" in v && typeof v.integerValue === "string" &&
        /^-?(0|[1-9][0-9]*)$/.test(v.integerValue)) {
      const n = Number(v.integerValue);
      if (!Number.isSafeInteger(n)) throw new Error("unsafe Firestore integer");
      return n;
    }
    if ("mapValue" in v && v.mapValue && typeof v.mapValue === "object" &&
        !Array.isArray(v.mapValue)) {
      const map = v.mapValue as Record<string, unknown>;
      if (Object.keys(map).some((key) => key !== "fields")) throw new Error("invalid map");
      const nested = map.fields ?? {};
      if (!nested || typeof nested !== "object" || Array.isArray(nested)) {
        throw new Error("invalid map fields");
      }
      return decodeFields(nested as Record<string, unknown>, depth + 1);
    }
    throw new Error("unsupported Firestore referral value");
  }
  function decodeFields(input: Record<string, unknown>, depth: number): Record<string, unknown> {
    const result: Record<string, unknown> = Object.create(null);
    for (const [key, value] of Object.entries(input)) {
      if (!/^[A-Za-z][A-Za-z0-9_]{0,127}$/.test(key)) throw new Error("invalid field name");
      result[key] = decode(value, depth);
    }
    return result;
  }
  return decodeFields(fields, 0);
}
