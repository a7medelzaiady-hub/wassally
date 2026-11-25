/**
 * Firebase Auth, not client input, establishes whether this is the original
 * Google registration session. It remains true while that first session is
 * active (even if the user takes time to finish the in-app dialog), but turns
 * false after any later sign-in.
 */
export function isOriginalRegistrationSession(
  createdAtMs: unknown,
  lastLoginAtMs: unknown,
  authTimeMs: unknown,
): boolean {
  return typeof createdAtMs === "number" && Number.isSafeInteger(createdAtMs) &&
    createdAtMs > 0 &&
    typeof lastLoginAtMs === "number" && Number.isSafeInteger(lastLoginAtMs) &&
    typeof authTimeMs === "number" && Number.isSafeInteger(authTimeMs) &&
    Math.abs(authTimeMs - createdAtMs) <= 5_000 &&
    Math.abs(lastLoginAtMs - createdAtMs) <= 5_000;
}
