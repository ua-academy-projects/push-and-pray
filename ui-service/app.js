const API_BASE = "http://192.168.0.51:8081";

const form = document.getElementById("search-form");
const cityInput = document.getElementById("city-input");
const countryInput = document.getElementById("country-input");
const statusEl = document.getElementById("status");
const resultEl = document.getElementById("result");
const submitButton = form.querySelector("button");

const historyListEl = document.getElementById("history-list");
const historyStatusEl = document.getElementById("history-status");
const historyRefreshButton = document.getElementById("history-refresh");

const trendsTrigger = document.getElementById("trends-trigger");
const trendsModal = document.getElementById("trends-modal");
const trendsClose = document.getElementById("trends-close");
const trendsTitle = document.getElementById("trends-title");
const trendsStatus = document.getElementById("trends-status");
const metricTabs = document.getElementById("metric-tabs");
const rangeTabs = document.getElementById("range-tabs");
const chartContainer = document.getElementById("chart-container");
const chartSvg = document.getElementById("trends-chart");
const chartTooltip = document.getElementById("chart-tooltip");
const tableToggle = document.getElementById("table-toggle");
const tableWrap = document.getElementById("table-wrap");
const tableBody = document.getElementById("trends-table-body");
const tableMetricHead = document.getElementById("table-metric-head");

const TRACKED_CITIES_KEY = "weatherapp:trackedCities";
const SESSION_ID_KEY = "weatherapp:sessionId";

function generateId() {
  if (window.crypto && typeof window.crypto.randomUUID === "function") {
    return window.crypto.randomUUID();
  }
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
}

function getSessionId() {
  let id = sessionStorage.getItem(SESSION_ID_KEY);
  if (!id) {
    id = generateId();
    sessionStorage.setItem(SESSION_ID_KEY, id);
  }
  return id;
}

function getTrackedCities() {
  try {
    const parsed = JSON.parse(localStorage.getItem(TRACKED_CITIES_KEY) || "[]");
    return Array.isArray(parsed) ? parsed : [];
  } catch (err) {
    console.error("Failed to read tracked cities from localStorage", err);
    return [];
  }
}

function addTrackedCity(city, country) {
  const cities = getTrackedCities();
  const exists = cities.some(
    (c) => c.city.toLowerCase() === city.toLowerCase() && c.country.toLowerCase() === country.toLowerCase()
  );
  if (!exists) {
    cities.push({ city, country });
    cities.sort((a, b) => a.city.localeCompare(b.city));
    localStorage.setItem(TRACKED_CITIES_KEY, JSON.stringify(cities));
  }
}

const SVG_NS = "http://www.w3.org/2000/svg";
const METRICS = [
  { key: "temperatureC", label: "Temperature", unit: "°C", digits: 1 },
  { key: "humidity", label: "Humidity", unit: "%", digits: 0 },
  { key: "windSpeed", label: "Wind", unit: " kph", digits: 1 },
  { key: "pressure", label: "Pressure", unit: " mb", digits: 0 },
];
const CHART_W = 640;
const CHART_H = 260;
const CHART_MARGIN = { top: 14, right: 16, bottom: 30, left: 46 };
const RANGE_DAYS = { "1d": 1, "7d": 7, "30d": 30 };
const DEFAULT_RANGE = "7d";

let trendsReadings = [];
let activeMetricKey = METRICS[0].key;
let activeRangeKey = DEFAULT_RANGE;

const ICONS = {
  sun: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><circle cx="12" cy="12" r="4.5"/><path d="M12 2.5v3M12 18.5v3M21.5 12h-3M5.5 12h-3M18.5 5.5l-2 2M7.5 16.5l-2 2M18.5 18.5l-2-2M7.5 7.5l-2-2"/></svg>',
  cloud: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M6.5 18h11a4 4 0 0 0 .5-7.97A5.5 5.5 0 0 0 7.4 8.53 4.25 4.25 0 0 0 6.5 18Z"/></svg>',
  rain: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M6.5 14.5h11a4 4 0 0 0 .5-7.97A5.5 5.5 0 0 0 7.4 5.03 4.25 4.25 0 0 0 6.5 14.5Z"/><path d="M9 18.5l-1 2.5M13 18.5l-1 2.5M17 18.5l-1 2.5"/></svg>',
  storm: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M6.5 13.5h11a4 4 0 0 0 .5-7.97A5.5 5.5 0 0 0 7.4 4.03 4.25 4.25 0 0 0 6.5 13.5Z"/><path d="M13 14l-3 5h3l-2 4"/></svg>',
  snow: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M6.5 13.5h11a4 4 0 0 0 .5-7.97A5.5 5.5 0 0 0 7.4 4.03 4.25 4.25 0 0 0 6.5 13.5Z"/><path d="M9 17.5v4M7 18.5l4 2M11 18.5l-4 2M15 17.5v4M13 18.5l4 2M17 18.5l-4 2"/></svg>',
  fog: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><path d="M4 9h11M4 13h16M4 17h13"/></svg>',
};

const TONE_FOR_KEY = {
  sun: "warm",
  cloud: "neutral",
  rain: "cool",
  storm: "cool",
  snow: "cool",
  fog: "neutral",
};

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  const city = cityInput.value.trim();
  const country = countryInput.value.trim();
  if (!city || !country) {
    return;
  }

  const ok = await fetchWeather(city, country);
  if (ok) {
    addTrackedCity(city, country);
  }
  await loadHistory();
});

historyRefreshButton.addEventListener("click", () => {
  loadHistory(true);
});

trendsTrigger.addEventListener("click", () => {
  openTrends(currentCity, currentCountry);
});

trendsClose.addEventListener("click", () => {
  trendsModal.close();
});

trendsModal.addEventListener("click", (event) => {
  if (event.target === trendsModal) {
    trendsModal.close();
  }
});

trendsModal.addEventListener("close", () => {
  trendsTrigger.focus();
});

metricTabs.addEventListener("click", (event) => {
  const button = event.target.closest(".metric-tab");
  if (!button) {
    return;
  }
  setActiveMetric(button.dataset.metric);
});

rangeTabs.addEventListener("click", (event) => {
  const button = event.target.closest(".metric-tab");
  if (!button) {
    return;
  }
  setActiveRange(button.dataset.range);
});

tableToggle.addEventListener("click", () => {
  const showingTable = !tableWrap.hidden;
  tableWrap.hidden = showingTable;
  chartContainer.hidden = !showingTable;
  tableToggle.textContent = showingTable ? "View as table" : "View as chart";
});

loadHistory();

async function fetchWeather(city, country) {
  setLoading(true);
  hideResult();
  showStatus(`Loading weather for "${city}, ${country}"...`);

  try {
    const params = new URLSearchParams({ city, country });
    const response = await fetch(`${API_BASE}/api/v1/weather/current?${params}`);

    if (!response.ok) {
      throw new Error(`Server responded with ${response.status}`);
    }

    const data = await response.json();
    renderResult(data);
    hideStatus();
    return true;
  } catch (err) {
    showStatus(
      `Could not load weather for "${city}, ${country}". Check that history-service and proxy-service are running, and that the city name is valid.`,
      true
    );
    console.error(err);
    return false;
  } finally {
    setLoading(false);
  }
}

function conditionKey(condition) {
  const text = (condition || "").toLowerCase();
  if (/thunder|storm/.test(text)) return "storm";
  if (/snow|sleet|ice/.test(text)) return "snow";
  if (/rain|drizzle|shower/.test(text)) return "rain";
  if (/fog|mist|haze/.test(text)) return "fog";
  if (/clear|sun/.test(text)) return "sun";
  return "cloud";
}

function formatMetric(value, unit, digits = 0) {
  if (value === null || value === undefined) {
    return "—";
  }
  return `${Number(value).toFixed(digits)}${unit}`;
}

let currentCity = "";
let currentCountry = "";

function renderResult(data) {
  const key = conditionKey(data.condition);

  currentCity = data.city;
  currentCountry = data.country;

  resultEl.dataset.tone = TONE_FOR_KEY[key];
  document.getElementById("result-icon").innerHTML = ICONS[key];
  document.getElementById("result-city").textContent = data.city;
  document.getElementById("result-country").textContent = data.country;
  document.getElementById("result-temp").textContent = Math.round(data.temperatureC);
  document.getElementById("result-condition").textContent = data.condition || "No condition reported";
  document.getElementById("result-humidity").textContent = formatMetric(data.humidity, "%");
  document.getElementById("result-wind").textContent = formatMetric(data.windSpeed, " kph", 1);
  document.getElementById("result-pressure").textContent = formatMetric(data.pressure, " mb", 0);
  document.getElementById("result-observed").textContent = data.fetchedAt
    ? `Updated ${formatTimestamp(data.fetchedAt)}`
    : "";
  resultEl.hidden = false;
}

function hideResult() {
  resultEl.hidden = true;
}

function showStatus(message, isError = false) {
  statusEl.textContent = message;
  statusEl.classList.toggle("error", isError);
  statusEl.hidden = false;
}

function hideStatus() {
  statusEl.hidden = true;
}

function setLoading(isLoading) {
  submitButton.disabled = isLoading;
  cityInput.disabled = isLoading;
  countryInput.disabled = isLoading;
}

async function loadHistory(force = false) {
  showHistoryStatus("Loading tracked cities...");

  try {
    const cities = getTrackedCities();
    const records = await Promise.all(
      cities.map(async ({ city, country }) => {
        const params = new URLSearchParams({ city, country });
        if (force) {
          params.set("force", "true");
        }
        const currentResponse = await fetch(`${API_BASE}/api/v1/weather/current?${params}`);
        return currentResponse.ok ? currentResponse.json() : null;
      })
    );
    renderHistory(records.filter(Boolean));
    hideHistoryStatus();
  } catch (err) {
    showHistoryStatus("Could not load tracked cities.", true);
    console.error(err);
  }
}

function renderHistory(records) {
  historyListEl.innerHTML = "";

  if (!records || records.length === 0) {
    showHistoryStatus("No tracked cities yet.");
    return;
  }

  for (const record of records) {
    const key = conditionKey(record.condition);

    const item = document.createElement("li");
    item.className = "log-item";
    item.dataset.tone = TONE_FOR_KEY[key];

    const button = document.createElement("button");
    button.type = "button";
    button.className = "log-item-button";
    button.innerHTML = `
      <span class="log-item-icon">${ICONS[key]}</span>
      <span class="log-item-main">
        <span class="log-item-loc">${record.city}, ${record.country}</span>
        <span class="log-item-meta">${formatMetric(record.humidity, "% hum.")} · ${formatMetric(record.windSpeed, " kph", 1)} · ${formatTimestamp(record.fetchedAt)}</span>
      </span>
      <span class="log-item-temp">${Math.round(record.temperatureC)}°C</span>
    `;
    button.addEventListener("click", () => {
      cityInput.value = record.city;
      countryInput.value = record.country;
      fetchWeather(record.city, record.country);
    });

    item.appendChild(button);
    historyListEl.appendChild(item);
  }
}

// The backend's clock is UTC, but Spring serializes LocalDateTime without a
// timezone marker (e.g. "2026-07-23T13:49:49"). JS's Date parser treats a
// timezone-less string as already being in the browser's local time, so
// without this it silently reads UTC timestamps as local ones. Appending "Z"
// tells it these are actually UTC instants.
function parseServerTimestamp(value) {
  if (!value) {
    return null;
  }
  const hasZone = /(Z|[+-]\d{2}:?\d{2})$/.test(value);
  return new Date(hasZone ? value : `${value}Z`);
}

function formatTimestamp(value) {
  const date = parseServerTimestamp(value);
  return date && !Number.isNaN(date.getTime()) ? date.toLocaleString() : "";
}

function showHistoryStatus(message, isError = false) {
  historyStatusEl.textContent = message;
  historyStatusEl.classList.toggle("error", isError);
  historyStatusEl.hidden = false;
  historyListEl.innerHTML = "";
}

function hideHistoryStatus() {
  historyStatusEl.hidden = true;
}

async function openTrends(city, country) {
  if (!city || !country) {
    return;
  }

  trendsTitle.textContent = `${city}, ${country}`;
  tableWrap.hidden = true;
  chartContainer.hidden = false;
  tableToggle.textContent = "View as table";
  trendsModal.showModal();

  const preferences = await fetchPreferences();
  activeRangeKey = preferences.range;
  activeMetricKey = preferences.metric;
  updateRangeButtons();
  updateMetricButtons();
  await loadTrendsHistory();
}

async function loadTrendsHistory() {
  clearChart();
  showTrendsStatus("Loading history...");

  try {
    const { from, to } = rangeBounds(activeRangeKey);
    const params = new URLSearchParams({ city: currentCity, country: currentCountry, from, to });
    const response = await fetch(`${API_BASE}/api/v1/weather/history?${params}`);
    if (!response.ok) {
      throw new Error(`Server responded with ${response.status}`);
    }
    trendsReadings = await response.json();
    hideTrendsStatus();
    renderTrends();
  } catch (err) {
    trendsReadings = [];
    showTrendsStatus("Could not load historical data.", true);
    console.error(err);
  }
}

function rangeBounds(rangeKey) {
  const days = RANGE_DAYS[rangeKey] ?? RANGE_DAYS[DEFAULT_RANGE];
  const now = Date.now();
  return {
    from: new Date(now - days * 86400000).toISOString().slice(0, 19),
    to: new Date(now).toISOString().slice(0, 19),
  };
}

async function fetchPreferences() {
  const fallback = { range: DEFAULT_RANGE, metric: METRICS[0].key };
  try {
    const response = await fetch(`${API_BASE}/api/v1/preferences`, {
      headers: { "X-Session-Id": getSessionId() },
    });
    if (!response.ok) {
      return fallback;
    }
    const data = await response.json();
    return {
      range: RANGE_DAYS[data.range] ? data.range : fallback.range,
      metric: METRICS.some((m) => m.key === data.metric) ? data.metric : fallback.metric,
    };
  } catch (err) {
    console.error("Failed to load preferences", err);
    return fallback;
  }
}

async function savePreferences(partial) {
  try {
    await fetch(`${API_BASE}/api/v1/preferences`, {
      method: "PUT",
      headers: {
        "X-Session-Id": getSessionId(),
        "Content-Type": "application/json",
      },
      body: JSON.stringify(partial),
    });
  } catch (err) {
    console.error("Failed to save preferences", err);
  }
}

function updateRangeButtons() {
  for (const button of rangeTabs.querySelectorAll(".metric-tab")) {
    button.setAttribute("aria-pressed", String(button.dataset.range === activeRangeKey));
  }
}

function setActiveRange(rangeKey) {
  if (rangeKey === activeRangeKey) {
    return;
  }
  activeRangeKey = rangeKey;
  updateRangeButtons();
  savePreferences({ range: rangeKey });
  loadTrendsHistory();
}

function updateMetricButtons() {
  for (const button of metricTabs.querySelectorAll(".metric-tab")) {
    button.setAttribute("aria-pressed", String(button.dataset.metric === activeMetricKey));
  }
}

function setActiveMetric(metricKey) {
  if (metricKey === activeMetricKey) {
    return;
  }
  activeMetricKey = metricKey;
  updateMetricButtons();
  savePreferences({ metric: metricKey });
  renderTrends();
}

function renderTrends() {
  const metric = METRICS.find((m) => m.key === activeMetricKey);
  tableMetricHead.textContent = `${metric.label} (${metric.unit.trim()})`;
  renderChart(metric);
  renderTable(metric);
}

function clearChart() {
  chartSvg.replaceChildren();
  chartTooltip.hidden = true;
}

function renderChartEmpty(message) {
  clearChart();
  const text = document.createElementNS(SVG_NS, "text");
  text.setAttribute("x", CHART_W / 2);
  text.setAttribute("y", CHART_H / 2);
  text.setAttribute("text-anchor", "middle");
  text.setAttribute("font-family", "IBM Plex Sans, sans-serif");
  text.setAttribute("font-size", "13");
  text.setAttribute("fill", "var(--ink-soft)");
  text.textContent = message;
  chartSvg.appendChild(text);
}

function niceTicks(min, max, count) {
  if (min === max) {
    min -= 1;
    max += 1;
  }
  const rawStep = (max - min) / count;
  const magnitude = Math.pow(10, Math.floor(Math.log10(rawStep)));
  const normalized = rawStep / magnitude;
  let step;
  if (normalized < 1.5) step = magnitude;
  else if (normalized < 3) step = 2 * magnitude;
  else if (normalized < 7) step = 5 * magnitude;
  else step = 10 * magnitude;

  const niceMin = Math.floor(min / step) * step;
  const niceMax = Math.ceil(max / step) * step;
  const ticks = [];
  for (let v = niceMin; v <= niceMax + step / 2; v += step) {
    ticks.push(Math.round(v * 1000) / 1000);
  }
  return ticks;
}

function formatAxisTime(ms) {
  return new Date(ms).toLocaleString(undefined, { hour: "2-digit", minute: "2-digit" });
}

function formatAxisDay(ms) {
  return new Date(ms).toLocaleString(undefined, { month: "short", day: "numeric" });
}

function renderChart(metric) {
  clearChart();

  const points = trendsReadings
    .map((r) => ({ t: parseServerTimestamp(r.fetchedAt)?.getTime(), v: r[metric.key] }))
    .filter((p) => Number.isFinite(p.t) && p.v !== null && p.v !== undefined && Number.isFinite(Number(p.v)))
    .sort((a, b) => a.t - b.t);

  if (points.length === 0) {
    renderChartEmpty(`No ${metric.label.toLowerCase()} history yet for this city.`);
    return;
  }

  const plotW = CHART_W - CHART_MARGIN.left - CHART_MARGIN.right;
  const plotH = CHART_H - CHART_MARGIN.top - CHART_MARGIN.bottom;

  const tMin = points[0].t;
  const tMax = points[points.length - 1].t;
  const values = points.map((p) => p.v);
  const yTicks = niceTicks(Math.min(...values), Math.max(...values), 4);
  const yDomainMin = yTicks[0];
  const yDomainMax = yTicks[yTicks.length - 1];

  const xScale = (t) =>
    tMax === tMin ? CHART_MARGIN.left + plotW / 2 : CHART_MARGIN.left + ((t - tMin) / (tMax - tMin)) * plotW;
  const yScale = (v) =>
    yDomainMax === yDomainMin
      ? CHART_MARGIN.top + plotH / 2
      : CHART_MARGIN.top + plotH - ((v - yDomainMin) / (yDomainMax - yDomainMin)) * plotH;

  for (const tick of yTicks) {
    const y = yScale(tick);
    const gridline = document.createElementNS(SVG_NS, "line");
    gridline.setAttribute("x1", CHART_MARGIN.left);
    gridline.setAttribute("x2", CHART_W - CHART_MARGIN.right);
    gridline.setAttribute("y1", y);
    gridline.setAttribute("y2", y);
    gridline.setAttribute("stroke", "var(--line)");
    gridline.setAttribute("stroke-width", "1");
    chartSvg.appendChild(gridline);

    const label = document.createElementNS(SVG_NS, "text");
    label.setAttribute("x", CHART_MARGIN.left - 8);
    label.setAttribute("y", y + 3);
    label.setAttribute("text-anchor", "end");
    label.setAttribute("font-family", "IBM Plex Mono, monospace");
    label.setAttribute("font-size", "10");
    label.setAttribute("fill", "var(--ink-soft)");
    label.textContent = formatMetric(tick, metric.unit, metric.digits);
    chartSvg.appendChild(label);
  }

  // 100px covers the widest possible label ("Jul 23 09:01 AM"), so even two
  // full-length labels placed back to back never touch.
  const minLabelGap = 100;
  const lastIdx = points.length - 1;
  const labelIndices = [0];
  let lastLabelX = xScale(points[0].t);
  for (let i = 1; i < points.length; i++) {
    const x = xScale(points[i].t);
    if (x - lastLabelX >= minLabelGap) {
      labelIndices.push(i);
      lastLabelX = x;
    }
  }
  if (labelIndices[labelIndices.length - 1] !== lastIdx) {
    const lastX = xScale(points[lastIdx].t);
    if (lastX - lastLabelX < minLabelGap && labelIndices.length > 1) {
      labelIndices[labelIndices.length - 1] = lastIdx;
    } else {
      labelIndices.push(lastIdx);
    }
  }

  let prevDayKey = null;
  labelIndices.forEach((idx) => {
    const point = points[idx];
    const x = xScale(point.t);
    const dayKey = new Date(point.t).toDateString();
    const showDay = dayKey !== prevDayKey;
    prevDayKey = dayKey;

    const label = document.createElementNS(SVG_NS, "text");
    label.setAttribute("x", x);
    label.setAttribute("y", CHART_H - CHART_MARGIN.bottom + 18);
    label.setAttribute(
      "text-anchor",
      idx === 0 ? "start" : idx === lastIdx ? "end" : "middle"
    );
    label.setAttribute("font-family", "IBM Plex Mono, monospace");
    label.setAttribute("font-size", "10");
    label.setAttribute("fill", "var(--ink-soft)");
    label.textContent = showDay ? `${formatAxisDay(point.t)} ${formatAxisTime(point.t)}` : formatAxisTime(point.t);
    chartSvg.appendChild(label);
  });

  const pathData = points
    .map((p, i) => `${i === 0 ? "M" : "L"}${xScale(p.t).toFixed(1)},${yScale(p.v).toFixed(1)}`)
    .join(" ");
  const path = document.createElementNS(SVG_NS, "path");
  path.setAttribute("d", pathData);
  path.setAttribute("fill", "none");
  path.setAttribute("stroke", "var(--brass)");
  path.setAttribute("stroke-width", "2");
  path.setAttribute("stroke-linejoin", "round");
  path.setAttribute("stroke-linecap", "round");
  chartSvg.appendChild(path);

  const last = points[points.length - 1];
  const lastX = xScale(last.t);
  const lastY = yScale(last.v);

  const ring = document.createElementNS(SVG_NS, "circle");
  ring.setAttribute("cx", lastX);
  ring.setAttribute("cy", lastY);
  ring.setAttribute("r", 6);
  ring.setAttribute("fill", "none");
  ring.setAttribute("stroke", "var(--panel-bg)");
  ring.setAttribute("stroke-width", "2");
  chartSvg.appendChild(ring);

  const marker = document.createElementNS(SVG_NS, "circle");
  marker.setAttribute("cx", lastX);
  marker.setAttribute("cy", lastY);
  marker.setAttribute("r", 4);
  marker.setAttribute("fill", "var(--brass)");
  chartSvg.appendChild(marker);

  const nearRightEdge = lastX > CHART_W - CHART_MARGIN.right - 70;
  const valueLabel = document.createElementNS(SVG_NS, "text");
  valueLabel.setAttribute("x", nearRightEdge ? lastX - 10 : lastX + 10);
  valueLabel.setAttribute("y", lastY - 8);
  valueLabel.setAttribute("text-anchor", nearRightEdge ? "end" : "start");
  valueLabel.setAttribute("font-family", "IBM Plex Mono, monospace");
  valueLabel.setAttribute("font-size", "11");
  valueLabel.setAttribute("font-weight", "500");
  valueLabel.setAttribute("fill", "var(--ink)");
  valueLabel.textContent = formatMetric(last.v, metric.unit, metric.digits);
  chartSvg.appendChild(valueLabel);

  attachChartInteraction(points, xScale, yScale, metric);
}

function attachChartInteraction(points, xScale, yScale, metric) {
  const crosshair = document.createElementNS(SVG_NS, "line");
  crosshair.setAttribute("y1", CHART_MARGIN.top);
  crosshair.setAttribute("y2", CHART_H - CHART_MARGIN.bottom);
  crosshair.setAttribute("stroke", "var(--ink-soft)");
  crosshair.setAttribute("stroke-width", "1");
  crosshair.setAttribute("opacity", "0");
  chartSvg.appendChild(crosshair);

  const hoverDot = document.createElementNS(SVG_NS, "circle");
  hoverDot.setAttribute("r", 5);
  hoverDot.setAttribute("fill", "var(--brass)");
  hoverDot.setAttribute("stroke", "var(--panel-bg)");
  hoverDot.setAttribute("stroke-width", "2");
  hoverDot.setAttribute("opacity", "0");
  chartSvg.appendChild(hoverDot);

  const hitLayer = document.createElementNS(SVG_NS, "rect");
  hitLayer.setAttribute("x", CHART_MARGIN.left);
  hitLayer.setAttribute("y", CHART_MARGIN.top);
  hitLayer.setAttribute("width", CHART_W - CHART_MARGIN.left - CHART_MARGIN.right);
  hitLayer.setAttribute("height", CHART_H - CHART_MARGIN.top - CHART_MARGIN.bottom);
  hitLayer.setAttribute("fill", "transparent");
  chartSvg.appendChild(hitLayer);

  const updateAt = (clientX) => {
    const svgRect = chartSvg.getBoundingClientRect();
    const svgX = (clientX - svgRect.left) * (CHART_W / svgRect.width);

    let nearest = points[0];
    let nearestDist = Infinity;
    for (const point of points) {
      const dist = Math.abs(xScale(point.t) - svgX);
      if (dist < nearestDist) {
        nearestDist = dist;
        nearest = point;
      }
    }

    const px = xScale(nearest.t);
    const py = yScale(nearest.v);

    crosshair.setAttribute("x1", px);
    crosshair.setAttribute("x2", px);
    crosshair.setAttribute("opacity", "1");
    hoverDot.setAttribute("cx", px);
    hoverDot.setAttribute("cy", py);
    hoverDot.setAttribute("opacity", "1");

    const containerRect = chartContainer.getBoundingClientRect();
    const pxRatio = svgRect.width / CHART_W;
    const pyRatio = svgRect.height / CHART_H;

    chartTooltip.replaceChildren();
    const valueLine = document.createElement("strong");
    valueLine.textContent = formatMetric(nearest.v, metric.unit, metric.digits);
    const timeLine = document.createElement("span");
    timeLine.textContent = formatTimestamp(nearest.t);
    chartTooltip.appendChild(valueLine);
    chartTooltip.appendChild(timeLine);
    chartTooltip.hidden = false;

    const rawLeft = svgRect.left - containerRect.left + px * pxRatio;
    const half = chartTooltip.offsetWidth / 2;
    const clampedLeft = Math.min(Math.max(rawLeft, half + 4), containerRect.width - half - 4);
    chartTooltip.style.left = `${clampedLeft}px`;
    chartTooltip.style.top = `${svgRect.top - containerRect.top + py * pyRatio - 10}px`;
  };

  hitLayer.addEventListener("pointermove", (event) => updateAt(event.clientX));
  hitLayer.addEventListener("pointerleave", () => {
    crosshair.setAttribute("opacity", "0");
    hoverDot.setAttribute("opacity", "0");
    chartTooltip.hidden = true;
  });
}

function renderTable(metric) {
  tableBody.replaceChildren();

  const rows = trendsReadings.filter(
    (r) => r[metric.key] !== null && r[metric.key] !== undefined
  );

  if (rows.length === 0) {
    const row = document.createElement("tr");
    const cell = document.createElement("td");
    cell.colSpan = 2;
    cell.textContent = `No ${metric.label.toLowerCase()} history yet for this city.`;
    row.appendChild(cell);
    tableBody.appendChild(row);
    return;
  }

  for (const reading of rows) {
    const row = document.createElement("tr");
    const timeCell = document.createElement("td");
    timeCell.textContent = formatTimestamp(reading.fetchedAt);
    const valueCell = document.createElement("td");
    valueCell.textContent = formatMetric(reading[metric.key], metric.unit, metric.digits);
    row.appendChild(timeCell);
    row.appendChild(valueCell);
    tableBody.appendChild(row);
  }
}

function showTrendsStatus(message, isError = false) {
  trendsStatus.textContent = message;
  trendsStatus.classList.toggle("error", isError);
  trendsStatus.hidden = false;
}

function hideTrendsStatus() {
  trendsStatus.hidden = true;
}