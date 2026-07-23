import { describe, expect, it } from "vitest";
import { degreesToCompass } from "../src/utils/windDirection";

describe("degreesToCompass", () => {
  it("maps cardinal directions correctly", () => {
    expect(degreesToCompass(0)).toBe("N");
    expect(degreesToCompass(90)).toBe("E");
    expect(degreesToCompass(180)).toBe("S");
    expect(degreesToCompass(270)).toBe("W");
  });

  it("maps an intercardinal direction", () => {
    expect(degreesToCompass(220)).toBe("SW");
  });

  it("wraps around at 360 degrees", () => {
    expect(degreesToCompass(360)).toBe("N");
  });
});
