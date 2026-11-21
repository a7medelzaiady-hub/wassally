import { describe, expect, it } from "vitest";
import { serviceFeeFor } from "../src/index";

describe("serviceFeeFor (2%, min 5, max 15 EGP)", () => {
  it("matches the app calculation", () => {
    expect(serviceFeeFor(100)).toBe(5);
    expect(serviceFeeFor(437)).toBe(8.74);
    expect(serviceFeeFor(500)).toBe(10);
    expect(serviceFeeFor(750)).toBe(15);
    expect(serviceFeeFor(2000)).toBe(15);
    expect(serviceFeeFor(0)).toBe(0);
    expect(serviceFeeFor(-5)).toBe(0);
    expect(serviceFeeFor(Number.NaN)).toBe(0);
  });
});
