import { describe, expect, it } from "vitest";
import { getWeatherInfo } from "../src/utils/weatherCode";

describe("getWeatherInfo", () => {
  it("maps clear sky to different themes for day and night", () => {
    expect(getWeatherInfo(0, true).theme).toBe("clear-day");
    expect(getWeatherInfo(0, false).theme).toBe("clear-night");
  });

  it("maps known WMO codes to their documented descriptions", () => {
    expect(getWeatherInfo(3, true).description).toBe("Overcast");
    expect(getWeatherInfo(61, true).description).toBe("Slight rain");
    expect(getWeatherInfo(75, true).description).toBe("Heavy snow fall");
    expect(getWeatherInfo(95, true).description).toBe("Thunderstorm");
  });

  it("distinguishes heavy rain from regular rain for background theming", () => {
    expect(getWeatherInfo(63, true).theme).toBe("rain");
    expect(getWeatherInfo(65, true).theme).toBe("heavy-rain");
  });

  it("falls back gracefully for an unknown code instead of throwing", () => {
    const info = getWeatherInfo(9999, true);
    expect(info.description).toBe("Unknown conditions");
    expect(info.theme).toBeDefined();
  });
});
