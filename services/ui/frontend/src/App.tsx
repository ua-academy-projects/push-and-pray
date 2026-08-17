import {
  Activity,
  BarChart3,
  CalendarRange,
  Check,
  CloudOff,
  Database,
  Gauge,
  Layers3,
  RefreshCw,
  SlidersHorizontal,
  Waves,
} from "lucide-react";
import { lazy, Suspense, useEffect, useMemo, useState } from "react";

import { loadMarketData, loadPreferences, savePreferences } from "./api";
import {
  createChartGroups,
  fallbackColor,
  filterVisible,
  groupByInstrument,
  SERIES_COLORS,
  toSeriesPoints,
  uniqueChronological,
} from "./data";
import { eventTime, formatDateTime, formatPercent, formatPrice, unitShort } from "./format";
import type {
  ChartStyle,
  Instrument,
  Layout,
  LoadState,
  Metric,
  MovingAverage,
  Observation,
  Preferences,
  RangeValue,
  Scale,
  TableOrder,
} from "./types";

const ChartPanel = lazy(() => import("./ChartPanel"));

const DEFAULT_PREFERENCES: Preferences = {
  selected: null,
  range: "30",
  metric: "price",
  layout: "compare",
  style: "line",
  table_order: "desc",
  table_limit: 50,
  scale: "linear",
  moving_average: "off",
  smooth: true,
};

const rangeOptions: Array<{ value: RangeValue; label: string }> = [
  { value: "1", label: "24H" },
  { value: "7", label: "7D" },
  { value: "30", label: "30D" },
  { value: "90", label: "90D" },
  { value: "180", label: "6M" },
  { value: "365", label: "1Y" },
  { value: "all", label: "ALL" },
];

interface SegmentedProps<T extends string> {
  value: T;
  options: Array<{ value: T; label: string }>;
  onChange: (value: T) => void;
  disabled?: boolean;
}

function Segmented<T extends string>({
  value,
  options,
  onChange,
  disabled = false,
}: SegmentedProps<T>) {
  return (
    <div className={`segmented ${disabled ? "disabled" : ""}`}>
      {options.map((option) => (
        <button
          type="button"
          key={option.value}
          className={option.value === value ? "active" : ""}
          onClick={() => onChange(option.value)}
          disabled={disabled}
        >
          {option.label}
        </button>
      ))}
    </div>
  );
}

function deltaFor(item: Observation, history: Record<string, Observation[]>): number | null {
  const rows = uniqueChronological(history[item.instrument_code] ?? []);
  if (rows.length < 2) return null;
  const previous = rows.at(-2);
  if (!previous) return null;
  return (Number(item.price) / Number(previous.price) - 1) * 100;
}

function App() {
  const [preferences, setPreferences] = useState<Preferences>(DEFAULT_PREFERENCES);
  const [observations, setObservations] = useState<Observation[]>([]);
  const [latest, setLatest] = useState<Observation[]>([]);
  const [instruments, setInstruments] = useState<Instrument[]>([]);
  const [loadState, setLoadState] = useState<LoadState>("loading");
  const [errorMessage, setErrorMessage] = useState("");
  const [ready, setReady] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [sessionState, setSessionState] = useState<"saved" | "saving" | "local">("saving");
  const [lastRead, setLastRead] = useState<Date | null>(null);

  const applyMarketData = (data: Awaited<ReturnType<typeof loadMarketData>>) => {
    setLatest(data.latest);
    setObservations(data.observations);
    setInstruments(data.instruments);
    setLastRead(new Date());
  };

  useEffect(() => {
    let active = true;
    const bootstrap = async () => {
      const preferencePromise = loadPreferences()
        .then((stored) => ({ stored, sessionAvailable: true }))
        .catch(() => ({ stored: DEFAULT_PREFERENCES, sessionAvailable: false }));
      try {
        const [preferenceResult, marketData] = await Promise.all([
          preferencePromise,
          loadMarketData(),
        ]);
        if (!active) return;
        const selected =
          preferenceResult.stored.selected ??
          marketData.instruments.map((instrument) => instrument.code);
        setPreferences({ ...preferenceResult.stored, selected });
        setSessionState(preferenceResult.sessionAvailable ? "saved" : "local");
        applyMarketData(marketData);
        setLoadState("ready");
        setReady(true);
      } catch (error) {
        if (!active) return;
        setLoadState("error");
        setErrorMessage(error instanceof Error ? error.message : "Unknown error");
      }
    };
    void bootstrap();
    return () => {
      active = false;
    };
  }, []);

  useEffect(() => {
    if (!ready) return;
    setSessionState((current) => (current === "local" ? "local" : "saving"));
    const timer = window.setTimeout(() => {
      void savePreferences(preferences)
        .then(() => setSessionState("saved"))
        .catch(() => setSessionState("local"));
    }, 350);
    return () => window.clearTimeout(timer);
  }, [preferences, ready]);

  const refresh = async () => {
    setRefreshing(true);
    try {
      applyMarketData(await loadMarketData());
      setLoadState("ready");
      setErrorMessage("");
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : "Unknown error");
    } finally {
      setRefreshing(false);
    }
  };

  const updatePreference = <K extends keyof Preferences>(key: K, value: Preferences[K]) => {
    setPreferences((current) => ({ ...current, [key]: value }));
  };

  const selected = preferences.selected ?? [];
  const visible = useMemo(
    () => filterVisible(observations, selected, preferences.range),
    [observations, preferences.range, selected],
  );
  const history = useMemo(() => groupByInstrument(observations), [observations]);
  const chartGroups = useMemo(
    () =>
      createChartGroups(
        visible,
        instruments,
        preferences.metric,
        preferences.layout,
      ),
    [instruments, preferences.layout, preferences.metric, visible],
  );
  const visibleGroups = useMemo(() => groupByInstrument(visible), [visible]);
  const selectedSet = useMemo(() => new Set(selected), [selected]);

  const sortedTable = useMemo(() => {
    const direction = preferences.table_order === "asc" ? 1 : -1;
    return [...visible]
      .sort((a, b) => (Date.parse(eventTime(a)) - Date.parse(eventTime(b))) * direction)
      .slice(0, preferences.table_limit);
  }, [preferences.table_limit, preferences.table_order, visible]);

  const toggleInstrument = (code: string) => {
    const next = selectedSet.has(code)
      ? selected.filter((item) => item !== code)
      : [...selected, code];
    updatePreference("selected", next);
  };

  return (
    <div className="app-shell">
      <header className="topbar">
        <a className="brand" href="/" aria-label="PetroScope">
          <span className="brand-symbol"><Waves size={22} /></span>
          <span><strong>PetroScope</strong><small>Energy market research</small></span>
        </a>
        <div className="system-strip">
          <span><i className={loadState === "ready" ? "online" : "pending"} />History / PostgreSQL</span>
          <span>
            {sessionState === "saved" ? <Check size={13} /> : sessionState === "local" ? <CloudOff size={13} /> : <Activity size={13} />}
            {sessionState === "saved" ? "Session saved" : sessionState === "local" ? "Local defaults" : "Saving session"}
          </span>
          <time>{lastRead ? `${formatDateTime(lastRead)} UTC` : "Waiting for data"}</time>
        </div>
        <button className="refresh-button" type="button" onClick={() => void refresh()} disabled={refreshing}>
          <RefreshCw size={16} className={refreshing ? "spinning" : ""} />
          <span>{refreshing ? "Syncing" : "Refresh"}</span>
        </button>
      </header>

      <main>
        <section className="intro">
          <div className="intro-copy">
            <p className="overline">Persisted market observations · UTC normalized</p>
            <h1>Oil benchmarks,<br /><em>without the noise.</em></h1>
            <p>
              WTI, Brent і RBOB в одному дослідницькому просторі. Інтерфейс читає
              лише перевірені записи з PostgreSQL — жодних прямих запитів до market API.
            </p>
          </div>
          <aside className="protocol-card">
            <span className="protocol-icon"><Gauge size={20} /></span>
            <div>
              <p>Collection cadence</p>
              <strong>4 snapshots / day</strong>
              <span>00:00 · 06:00 · 12:00 · 18:00 UTC</span>
            </div>
            <div className="protocol-flow">
              {["API", "PG EVENT", "DB", "UI"].map((step, index) => (
                <span key={step}><b>{String(index + 1).padStart(2, "0")}</b>{step}</span>
              ))}
            </div>
          </aside>
        </section>

        {loadState === "error" ? (
          <section className="error-banner">
            <CloudOff size={22} />
            <div><strong>History Service unavailable</strong><span>{errorMessage}</span></div>
            <button type="button" onClick={() => void refresh()}>Try again</button>
          </section>
        ) : null}

        <section className="market-section">
          <div className="section-heading">
            <div><span>01</span><div><p>Latest persisted values</p><h2>Market snapshot</h2></div></div>
            <small>Market time, not polling time</small>
          </div>
          <div className="market-grid">
            {loadState === "loading"
              ? [1, 2, 3].map((item) => <div className="market-card skeleton" key={item} />)
              : latest.map((item, index) => {
                  const delta = deltaFor(item, history);
                  const color = SERIES_COLORS[item.instrument_code] ?? fallbackColor(index);
                  const points = toSeriesPoints(history[item.instrument_code] ?? [], "price");
                  const sparkline = points.slice(-20);
                  const min = sparkline.length ? Math.min(...sparkline.map((point) => point.raw)) : Number(item.price);
                  const max = sparkline.length ? Math.max(...sparkline.map((point) => point.raw)) : Number(item.price);
                  const span = Math.max(max - min, 0.001);
                  const path = sparkline.map((point, pointIndex) => {
                    const x = sparkline.length === 1 ? 50 : (pointIndex / (sparkline.length - 1)) * 100;
                    const y = 34 - ((point.raw - min) / span) * 28;
                    return `${pointIndex === 0 ? "M" : "L"} ${x.toFixed(2)} ${y.toFixed(2)}`;
                  }).join(" ");
                  return (
                    <article className="market-card" key={item.instrument_code} style={{ "--series": color } as React.CSSProperties}>
                      <header><span>{item.category === "gasoline" ? "REFINED PRODUCT" : "CRUDE BENCHMARK"}</span><i /></header>
                      <h3>{item.instrument_name}</h3>
                      <div className="market-value">
                        <strong>{formatPrice(item.price)}</strong>
                        <span>{item.currency}<br />/ {unitShort(item.unit)}</span>
                      </div>
                      <svg className="sparkline" viewBox="0 0 100 38" preserveAspectRatio="none" aria-hidden="true">
                        <path d={path} />
                      </svg>
                      <footer>
                        <span className={delta === null ? "" : delta >= 0 ? "up" : "down"}>
                          {delta === null ? "No previous point" : `${formatPercent(delta)} vs previous`}
                        </span>
                        <time>{formatDateTime(eventTime(item))} UTC</time>
                      </footer>
                    </article>
                  );
                })}
          </div>
        </section>

        <section className="analysis-section">
          <div className="section-heading">
            <div><span>02</span><div><p>Interactive time series</p><h2>Market analysis</h2></div></div>
            <div className="point-count"><strong>{visible.length}</strong><span>visible<br />observations</span></div>
          </div>

          <div className="analysis-layout">
            <aside className="filters">
              <div className="filters-title"><SlidersHorizontal size={17} /><strong>View controls</strong></div>
              <fieldset>
                <legend><Layers3 size={14} /> Instruments</legend>
                <div className="instrument-actions">
                  <button type="button" onClick={() => updatePreference("selected", instruments.map((item) => item.code))}>Select all</button>
                  <button type="button" onClick={() => updatePreference("selected", [])}>Clear</button>
                </div>
                <div className="instrument-list">
                  {instruments.map((instrument, index) => {
                    const color = SERIES_COLORS[instrument.code] ?? fallbackColor(index);
                    return (
                      <label key={instrument.code} style={{ "--series": color } as React.CSSProperties}>
                        <input
                          type="checkbox"
                          checked={selectedSet.has(instrument.code)}
                          onChange={() => toggleInstrument(instrument.code)}
                        />
                        <i />
                        <span><strong>{instrument.name}</strong><small>{unitShort(instrument.unit)}</small></span>
                      </label>
                    );
                  })}
                </div>
              </fieldset>
              <fieldset>
                <legend><CalendarRange size={14} /> Time range</legend>
                <Segmented value={preferences.range} options={rangeOptions} onChange={(value) => updatePreference("range", value)} />
              </fieldset>
              <fieldset>
                <legend><BarChart3 size={14} /> Value</legend>
                <Segmented<Metric>
                  value={preferences.metric}
                  options={[{ value: "price", label: "Price" }, { value: "change", label: "Δ %" }]}
                  onChange={(value) => updatePreference("metric", value)}
                />
              </fieldset>
              <fieldset>
                <legend>Layout</legend>
                <Segmented<Layout>
                  value={preferences.layout}
                  options={[{ value: "compare", label: "Compare" }, { value: "separate", label: "Panels" }]}
                  onChange={(value) => updatePreference("layout", value)}
                />
              </fieldset>
              <fieldset>
                <legend>Rendering</legend>
                <Segmented<ChartStyle>
                  value={preferences.style}
                  options={[{ value: "line", label: "Line" }, { value: "area", label: "Area" }, { value: "points", label: "Points" }]}
                  onChange={(value) => updatePreference("style", value)}
                />
              </fieldset>
              <fieldset>
                <legend>Scale</legend>
                <Segmented<Scale>
                  value={preferences.scale}
                  options={[{ value: "linear", label: "Linear" }, { value: "log", label: "Log" }]}
                  onChange={(value) => updatePreference("scale", value)}
                  disabled={preferences.metric === "change"}
                />
              </fieldset>
              <fieldset>
                <legend>Rolling average</legend>
                <Segmented<MovingAverage>
                  value={preferences.moving_average}
                  options={[{ value: "off", label: "Off" }, { value: "3", label: "MA 3" }, { value: "7", label: "MA 7" }]}
                  onChange={(value) => updatePreference("moving_average", value)}
                />
              </fieldset>
              <label className="switch-row">
                <span><strong>Smooth curve</strong><small>Visual interpolation only</small></span>
                <input type="checkbox" checked={preferences.smooth} onChange={(event) => updatePreference("smooth", event.target.checked)} />
                <i />
              </label>
            </aside>

            <div className="analysis-main">
              <div className="series-summary">
                {Object.entries(visibleGroups).map(([code, rows], index) => {
                  const points = toSeriesPoints(rows, "price");
                  if (!points.length) return null;
                  const first = points[0]!;
                  const last = points.at(-1)!;
                  const values = points.map((point) => point.raw);
                  const change = (last.raw / first.raw - 1) * 100;
                  const color = SERIES_COLORS[code] ?? fallbackColor(index);
                  return (
                    <article key={code} style={{ "--series": color } as React.CSSProperties}>
                      <span><i />{last.observation.instrument_name}</span>
                      <strong className={change >= 0 ? "up" : "down"}>{formatPercent(change)}</strong>
                      <dl>
                        <div><dt>Low</dt><dd>{formatPrice(Math.min(...values))}</dd></div>
                        <div><dt>High</dt><dd>{formatPrice(Math.max(...values))}</dd></div>
                        <div><dt>Points</dt><dd>{points.length}</dd></div>
                      </dl>
                    </article>
                  );
                })}
              </div>
              <div className="charts">
                {chartGroups.length ? chartGroups.map((group) => (
                  <Suspense key={group.key} fallback={<div className="chart-loading">Preparing chart engine…</div>}>
                    <ChartPanel
                      group={group}
                      metric={preferences.metric}
                      style={preferences.style}
                      scale={preferences.scale}
                      smooth={preferences.smooth}
                      movingAverage={preferences.moving_average}
                    />
                  </Suspense>
                )) : (
                  <div className="empty-state"><BarChart3 size={30} /><strong>No series selected</strong><span>Select at least one instrument in the controls.</span></div>
                )}
              </div>
            </div>
          </div>
        </section>

        <section className="ledger-section">
          <div className="section-heading ledger-heading">
            <div><span>03</span><div><p>PostgreSQL observation log</p><h2>Data ledger</h2></div></div>
            <div className="ledger-controls">
              <label><span>Order</span>
                <select value={preferences.table_order} onChange={(event) => updatePreference("table_order", event.target.value as TableOrder)}>
                  <option value="desc">Newest first</option><option value="asc">Oldest first</option>
                </select>
              </label>
              <label><span>Rows</span>
                <select value={preferences.table_limit} onChange={(event) => updatePreference("table_limit", Number(event.target.value) as Preferences["table_limit"])}>
                  {[25, 50, 100, 250].map((limit) => <option value={limit} key={limit}>{limit}</option>)}
                </select>
              </label>
            </div>
          </div>
          <div className="table-wrap">
            <table>
              <thead><tr><th>Market time / UTC</th><th>Instrument</th><th>Price</th><th>Collected / UTC</th><th>Source</th></tr></thead>
              <tbody>
                {sortedTable.map((item, index) => {
                  const color = SERIES_COLORS[item.instrument_code] ?? fallbackColor(index);
                  return (
                    <tr key={item.id}>
                      <td><time>{formatDateTime(eventTime(item))}</time><small>{item.source_period}</small></td>
                      <td><i style={{ background: color }} /><strong>{item.instrument_name}</strong></td>
                      <td><strong>{formatPrice(item.price)}</strong><small>{item.currency} / {unitShort(item.unit)}</small></td>
                      <td>{formatDateTime(item.fetched_at)}</td>
                      <td><span>{item.source}</span><small>{item.source_series_id}</small></td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </section>
      </main>

      <footer className="site-footer">
        <div><Database size={15} /><span>PostgreSQL is the market-data source of truth</span></div>
        <span>OilPriceAPI → Go Fetcher → PostgreSQL → History → UI</span>
        <b>PS / 03</b>
      </footer>
    </div>
  );
}

export default App;
