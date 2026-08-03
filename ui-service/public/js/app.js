import { createId, formatMoney, percentSeries } from './utils.js?v=12';

const API = window.RATEBOARD_CONFIG?.HISTORY_API_BASE_URL || 'http://127.0.0.1:8081/api/v1';
const PERIOD = {
  '1d': { label: '1 день', ms: 24 * 60 * 60_000, days: 1 },
  '7d': { label: '7 днів', ms: 7 * 86400_000, days: 7 },
  '30d': { label: '30 днів', ms: 30 * 86400_000, days: 30 },
  '90d': { label: '90 днів', ms: 90 * 86400_000, days: 90 },
  '365d': { label: '1 рік', ms: 365 * 86400_000, days: 365 },
};
const STEP = {
  '5m': { label: '5 хвилин', ms: 5 * 60_000 },
  '30m': { label: '30 хвилин', ms: 30 * 60_000 },
  '1h': { label: '1 година', ms: 60 * 60_000 },
  '4h': { label: '4 години', ms: 4 * 60 * 60_000 },
  '1d': { label: '1 день', ms: 24 * 60 * 60_000 },
};
const MARKET_PERIOD_LABELS = { '1h': '1 годину', '4h': '4 години', '1d': '1 день', '7d': '7 днів', '30d': '30 днів', '1y': '1 рік' };
const GRAPH_REFRESH_INTERVAL = 5 * 60_000;
const CHART_COLORS = ['#168a4b', '#3478c7', '#e28b25', '#9b63ce', '#d1495b', '#00a6a6', '#d36b20', '#5b6ee1', '#a44a9f', '#64748b'];
const state = {
  instruments: [], primary: null, comparisons: [], selected: new Set(), seriesColors: new Map(),
  period: '1d', step: '5m', mode: 'price', graphs: [], marketPeriod: '1d', marketMaps: [],
  activeTab: 'overview', hasRestoredPrimary: false, restoredPrimaryId: null,
  restoredComparisonIds: [], restoredGraphCards: [],
};
let graphRefreshRunning = false;
let sessionSaveTimer;
let sessionHydrated = false;
const $ = selector => document.querySelector(selector);

function showError(message = '') { const box = $('#global-error'); box.hidden = !message; box.textContent = message; }
async function api(path, options) {
  const response = await fetch(`${API}${path}`, { credentials: 'include', headers: { 'Content-Type': 'application/json' }, ...options });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(body.error?.message || body.detail || 'Не вдалося отримати дані');
  return body;
}

function sessionSnapshot() {
  return {
    active_tab: state.activeTab,
    period: state.period,
    step: state.step,
    mode: state.mode,
    market_period: state.marketPeriod,
    selected_instruments: [...state.selected],
    primary_instrument: state.primary?.instrument_id || null,
    comparison_instruments: state.comparisons.map(rate => rate.instrument_id),
    graph_cards: state.graphs.map(graph => ({
      instruments: [...graph.instruments],
      period: graph.period,
      step: graph.step,
      mode: graph.mode,
      colors: { ...graph.colors },
    })),
    theme: document.documentElement.dataset.theme,
  };
}
function saveSession() {
  if (!sessionHydrated) return;
  clearTimeout(sessionSaveTimer);
  sessionSaveTimer = setTimeout(() => localStorage.setItem('rateboard-session', JSON.stringify(sessionSnapshot())), 150);
}
async function restoreSession() {
  try {
    const saved = JSON.parse(localStorage.getItem('rateboard-session') || '{}');
    if (PERIOD[saved.period]) state.period = saved.period;
    if (STEP[saved.step]) state.step = saved.step;
    if (['price', 'percent'].includes(saved.mode)) state.mode = saved.mode;
    if (MARKET_PERIOD_LABELS[saved.market_period]) state.marketPeriod = saved.market_period;
    if (['overview', 'history', 'market-map'].includes(saved.active_tab)) state.activeTab = saved.active_tab;
    if (Array.isArray(saved.selected_instruments)) state.selected = new Set(saved.selected_instruments.slice(0, 5));
    if (Object.prototype.hasOwnProperty.call(saved, 'primary_instrument')) {
      state.hasRestoredPrimary = true;
      state.restoredPrimaryId = typeof saved.primary_instrument === 'string' ? saved.primary_instrument : null;
    }
    if (Array.isArray(saved.comparison_instruments)) state.restoredComparisonIds = saved.comparison_instruments.slice(0, 10);
    if (Array.isArray(saved.graph_cards)) state.restoredGraphCards = saved.graph_cards.slice(0, 20);
    if (['light', 'dark'].includes(saved.theme)) { document.documentElement.dataset.theme = saved.theme; localStorage.setItem('rateboard-theme', saved.theme); const dark = saved.theme === 'dark'; $('#theme-toggle').setAttribute('aria-pressed', dark); $('.theme-label').textContent = dark ? 'Світла тема' : 'Темна тема'; }
  } catch { /* Invalid local state is ignored and defaults remain usable. */ }
}
function syncControlsFromState() {
  for (const [selector, value, key] of [['#period-buttons', state.period, 'period'], ['#step-buttons', state.step, 'step'], ['#mode-buttons', state.mode, 'mode'], ['#market-period-buttons', state.marketPeriod, 'period']]) {
    document.querySelectorAll(`${selector} [data-${key}]`).forEach(button => button.classList.toggle('active', button.dataset[key] === value));
  }
}

function initTheme() {
  const button = $('#theme-toggle');
  const sync = () => { const dark = document.documentElement.dataset.theme === 'dark'; button.setAttribute('aria-pressed', dark); $('.theme-label').textContent = dark ? 'Світла тема' : 'Темна тема'; updateChartColors(); };
  button.addEventListener('click', () => { const theme = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark'; document.documentElement.dataset.theme = theme; localStorage.setItem('rateboard-theme', theme); sync(); saveSession(); }); sync();
}

function change(value, label) {
  if (value == null) return `<span class="stat"><span class="stat-label">${label}</span><span>—</span></span>`;
  const number = Number(value); return `<span class="stat"><span class="stat-label">${label}</span><span class="change ${number >= 0 ? 'positive' : 'negative'}">${number >= 0 ? '↑ +' : '↓ '}${number.toFixed(2)}%</span></span>`;
}
function rateCard(rate, removable = false, index = -1, showWeekly = false) {
  const weekly = showWeekly && rate.sparkline_7d?.length ? `<div class="hero-weekly"><span class="stat-label">Динаміка за 7 днів</span>${sparkline(rate.sparkline_7d)}</div>` : '';
  return `${removable ? `<button class="icon-button remove-card" type="button" data-index="${index}" aria-label="Прибрати картку">×</button>` : ''}<div class="rate-top"><div class="pair"><span class="asset-icon">${rate.base.slice(0, 2)}</span><div><h2>${rate.name}</h2><p>${rate.base} / ${rate.quote}</p></div></div><span class="source-chip">${rate.source}</span></div><div class="hero-value-row"><div class="hero-price">${formatMoney(rate.price, rate.quote)}</div>${weekly}</div><div class="rate-stats">${change(rate.change_1h_percent, 'За 1 годину')}${change(rate.change_24h_percent, 'За 1 день')}</div><p class="rate-meta">Збережено ${new Intl.DateTimeFormat('uk-UA', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(rate.requested_at || rate.source_timestamp))}</p>`;
}
async function hydrateWeekly(rate) {
  if (!rate || rate.kind !== 'crypto' || rate.sparkline_7d?.length) return rate;
  const end = new Date(); const start = new Date(end.getTime() - 7 * 86400_000);
  try {
    const params = new URLSearchParams({ instruments: rate.instrument_id, from: start.toISOString(), to: end.toISOString(), step: '4h', mode: 'price' });
    const data = await api(`/rates/history?${params}`); rate.sparkline_7d = data.series[0]?.points.map(point => point.value) || null;
  } catch { rate.sparkline_7d = null; }
  return rate;
}
function renderHero() {
  const primaryCard = $('#primary-card');
  primaryCard.hidden = !state.primary;
  if (state.primary) { primaryCard.classList.remove('skeleton'); primaryCard.innerHTML = rateCard(state.primary, true, 'primary', true); primaryCard.querySelector('.remove-card').addEventListener('click', () => { state.primary = null; renderHero(); saveSession(); }); }
  document.querySelectorAll('.comparison-rate').forEach(card => card.remove());
  state.comparisons.forEach((rate, index) => { const card = document.createElement('article'); card.className = 'rate-card hero-card comparison-rate'; card.innerHTML = rateCard(rate, true, index, true); $('#hero-grid').insertBefore(card, $('#add-compare')); });
  document.querySelectorAll('.comparison-rate .remove-card').forEach(button => button.addEventListener('click', () => { state.comparisons.splice(Number(button.dataset.index), 1); renderHero(); saveSession(); }));
}
function sparkline(values = []) {
  if (values.length < 2) return '<span class="sparkline-empty">—</span>';
  const width = 110; const height = 34; const min = Math.min(...values.map(Number)); const max = Math.max(...values.map(Number)); const span = max - min || 1;
  const points = values.map((value, index) => `${(index / (values.length - 1) * width).toFixed(1)},${(height - ((Number(value) - min) / span * height)).toFixed(1)}`).join(' ');
  const rising = Number(values.at(-1)) >= Number(values[0]);
  return `<svg class="sparkline ${rising ? 'positive-line' : 'negative-line'}" viewBox="0 0 ${width} ${height}" role="img" aria-label="Динаміка ціни за 7 днів"><polyline points="${points}" fill="none" vector-effect="non-scaling-stroke"></polyline></svg>`;
}
function marketRow(rate) {
  const day = rate.change_24h_percent == null ? '—' : `${Number(rate.change_24h_percent) >= 0 ? '↑ +' : '↓ '}${Number(rate.change_24h_percent).toFixed(2)}%`;
  if (rate.kind === 'crypto') {
    const hour = rate.change_1h_percent == null ? '—' : `${Number(rate.change_1h_percent) >= 0 ? '↑ +' : '↓ '}${Number(rate.change_1h_percent).toFixed(2)}%`;
    return `<button class="market-row crypto-market-row" type="button" data-id="${rate.instrument_id}"><span class="market-id"><span class="mini-icon">${rate.base.slice(0, 3)}</span><span class="market-name">${rate.name}<span class="market-symbol">${rate.base} / ${rate.quote}</span></span></span><span class="market-sparkline"><small>7 днів</small>${sparkline(rate.sparkline_7d)}</span><span class="market-price">${formatMoney(rate.price, rate.quote)}</span><span class="market-changes"><span><small>1 година</small><strong class="${rate.change_1h_percent == null ? '' : Number(rate.change_1h_percent) >= 0 ? 'positive' : 'negative'}">${hour}</strong></span><span><small>1 день</small><strong class="${rate.change_24h_percent == null ? '' : Number(rate.change_24h_percent) >= 0 ? 'positive' : 'negative'}">${day}</strong></span></span></button>`;
  }
  return `<button class="market-row" type="button" data-id="${rate.instrument_id}"><span class="market-id"><span class="mini-icon">${rate.base.slice(0, 3)}</span><span class="market-name">${rate.name}<span class="market-symbol">${rate.base} / ${rate.quote}</span></span></span><span class="market-price">${formatMoney(rate.price, rate.quote)}</span><span class="market-change">—</span></button>`;
}
function bindRows(container) { container.querySelectorAll('.market-row').forEach(row => row.addEventListener('click', () => selectPrimary(row.dataset.id))); }
async function selectPrimary(id) { try { const { items } = await api(`/rates/current?instruments=${encodeURIComponent(id)}`); state.primary = await hydrateWeekly(items[0]); renderHero(); saveSession(); scrollTo({ top: 0, behavior: 'smooth' }); } catch (error) { showError(error.message); } }

async function restoreCards(overviewRates) {
  const byId = new Map(overviewRates.map(rate => [rate.instrument_id, rate]));
  if (state.hasRestoredPrimary) state.primary = state.restoredPrimaryId && byId.has(state.restoredPrimaryId) ? byId.get(state.restoredPrimaryId) : null;
  state.comparisons = state.restoredComparisonIds
    .filter((id, index, ids) => id !== state.primary?.instrument_id && ids.indexOf(id) === index && byId.has(id))
    .map(id => byId.get(id));
  await Promise.all([hydrateWeekly(state.primary), ...state.comparisons.map(hydrateWeekly)]);
}

async function restoreGraphs() {
  const available = new Set(state.instruments.map(item => item.instrument_id));
  for (const saved of state.restoredGraphCards) {
    const instruments = Array.isArray(saved.instruments) ? saved.instruments.filter(id => available.has(id)).slice(0, 5) : [];
    if (!instruments.length || !PERIOD[saved.period] || !STEP[saved.step] || !['price', 'percent'].includes(saved.mode)) continue;
    const colors = Object.fromEntries(instruments.map((id, index) => {
      const savedColor = saved.colors?.[id];
      return [id, /^#[0-9a-f]{6}$/i.test(savedColor || '') ? savedColor : CHART_COLORS[index % CHART_COLORS.length]];
    }));
    const graph = { id: createId(), instruments, colors, period: saved.period, step: saved.step, mode: saved.mode, chart: null };
    const card = graphCard(graph);
    state.graphs.push(graph);
    wireGraph(graph);
    try {
      drawGraph(graph, await fetchGraph(graph));
    } catch (error) {
      card.querySelector('.chart-wrap').insertAdjacentHTML('beforeend', `<p class="empty graph-error">${escapeHTML(error.message)}</p>`);
    }
  }
}

async function loadOverview() {
  try {
    const data = await api('/overview'); state.primary = data.primary;
    state.instruments = [...data.crypto, ...data.fiat].map(({ instrument_id, kind, base, quote, name }) => ({ instrument_id, kind, base, quote, name }));
    $('#crypto-list').innerHTML = data.crypto.map(marketRow).join(''); $('#fiat-list').innerHTML = data.fiat.map(marketRow).join('');
    await restoreCards([...data.crypto, ...data.fiat]); bindRows($('#crypto-list')); bindRows($('#fiat-list')); renderHero(); renderInstrumentOptions(); renderPicker(); syncControlsFromState(); syncSelection();
    await restoreGraphs();
    if (state.activeTab !== 'overview') document.querySelector(`.tab[data-tab="${state.activeTab}"]`)?.click();
    return true;
  } catch (error) {
    showError(`${error.message}. Переконайтеся, що History Service запущений і PostgreSQL містить дані.`);
    $('#primary-card').innerHTML = '<p class="empty">Дані тимчасово недоступні.</p>';
    return false;
  }
}

async function refreshEverything() {
  const button = $('#refresh-button'); const rates = [state.primary, ...state.comparisons].filter(Boolean); button.disabled = true;
  try {
    if (rates.length) {
      const params = new URLSearchParams({ instruments: rates.map(item => item.instrument_id).join(',') });
      const { items } = await api(`/rates/stored-current?${params}`);
      const stored = new Map(items.map(item => [item.instrument_id, item]));
      const mergeStored = current => { const latest = stored.get(current.instrument_id); return latest ? { ...current, price: latest.price, source: latest.source, source_timestamp: latest.source_timestamp, requested_at: latest.requested_at, change_24h_percent: latest.change_24h_percent ?? current.change_24h_percent, market_cap: latest.market_cap ?? current.market_cap, rank: latest.rank ?? current.rank, sparkline_7d: null } : current; };
      if (state.primary) state.primary = mergeStored(state.primary);
      state.comparisons = state.comparisons.map(mergeStored);
      await Promise.all([hydrateWeekly(state.primary), ...state.comparisons.map(hydrateWeekly)]); renderHero();
    }
    await refreshGraphs();
  } catch (error) { showError(error.message); } finally { button.disabled = false; }
}

function renderPicker(query = '') {
  const used = new Set([state.primary?.instrument_id, ...state.comparisons.map(x => x.instrument_id)]);
  const matches = state.instruments.filter(item => !used.has(item.instrument_id) && `${item.name} ${item.base} ${item.quote}`.toLowerCase().includes(query.toLowerCase()));
  $('#compare-options').innerHTML = matches.map(item => `<button type="button" class="picker-item" data-id="${item.instrument_id}"><strong>${item.name}</strong><br><span class="empty">${item.base} / ${item.quote}</span></button>`).join('') || '<p class="empty">Усі доступні курси вже додано.</p>';
  $('#compare-options').querySelectorAll('button').forEach(button => button.addEventListener('click', async () => { try { const { items } = await api(`/rates/current?instruments=${encodeURIComponent(button.dataset.id)}`); state.comparisons.push(await hydrateWeekly(items[0])); renderHero(); renderPicker(); saveSession(); $('#compare-dialog').close(); } catch (error) { showError(error.message); } }));
}

function renderInstrumentOptions(query = '') {
  const matches = state.instruments.filter(item => `${item.name} ${item.base} ${item.quote}`.toLowerCase().includes(query.toLowerCase()));
  $('#instrument-options').innerHTML = matches.map(item => {
    const defaultColor = CHART_COLORS[state.instruments.findIndex(instrument => instrument.instrument_id === item.instrument_id) % CHART_COLORS.length];
    const color = state.seriesColors.get(item.instrument_id) || defaultColor;
    return `<label class="instrument-option"><input class="instrument-checkbox" type="checkbox" value="${item.instrument_id}" ${state.selected.has(item.instrument_id) ? 'checked' : ''}><span class="instrument-option-name"><strong>${item.name}</strong><br><small>${item.base}/${item.quote}</small></span><span class="color-control"><span class="sr-only">Колір ${item.name}</span><input class="series-color" type="color" value="${color}" data-instrument-id="${item.instrument_id}" aria-label="Колір графіка ${item.name}"></span></label>`;
  }).join('');
  $('#instrument-options').querySelectorAll('.instrument-checkbox').forEach(input => input.addEventListener('change', () => { if (input.checked && state.selected.size >= 5) { input.checked = false; showError('Можна обрати не більше п’яти валют.'); return; } input.checked ? state.selected.add(input.value) : state.selected.delete(input.value); syncSelection(); }));
  $('#instrument-options').querySelectorAll('.series-color').forEach(input => input.addEventListener('input', () => updateSeriesColor(input.dataset.instrumentId, input.value)));
  syncSelection();
}
function syncSelection() { $('#selection-count').textContent = state.selected.size; $('#instrument-trigger').textContent = state.selected.size ? [...state.selected].map(id => state.instruments.find(x => x.instrument_id === id)?.base).join(', ') : 'Оберіть до 5 валют'; if (state.selected.size) showError(); saveSession(); }

function updateSeriesColor(instrumentId, color) {
  state.seriesColors.set(instrumentId, color);
  state.graphs.forEach(graph => {
    graph.colors[instrumentId] = color;
    const dataset = graph.chart?.data.datasets.find(item => item.instrumentId === instrumentId);
    if (!dataset) return;
    dataset.borderColor = color;
    dataset.backgroundColor = color;
    dataset.pointBackgroundColor = color;
    graph.chart.update('none');
  });
  saveSession();
}

function css(name) { return getComputedStyle(document.documentElement).getPropertyValue(name).trim(); }
function updateChartColors() { state.graphs.forEach(graph => { if (!graph.chart) return; graph.chart.options.scales.x.grid.color = css('--border'); graph.chart.options.scales.y.grid.color = css('--border'); graph.chart.options.scales.x.ticks.color = css('--muted'); graph.chart.options.scales.y.ticks.color = css('--muted'); graph.chart.options.plugins.legend.labels.color = css('--text'); graph.chart.update('none'); }); }
function dateBounds(period) { const end = new Date(); const start = new Date(end.getTime() - PERIOD[period].ms); return { start, end }; }

async function fetchGraph(config) {
  const { start, end } = dateBounds(config.period); const params = new URLSearchParams({ instruments: config.instruments.join(','), from: start.toISOString(), to: end.toISOString(), step: config.step, mode: config.mode });
  const data = await api(`/rates/history?${params}`);
  const series = data.series.map(item => ({ ...item, points: item.points.filter(point => new Date(point.timestamp) >= start) }));
  if (!series.some(item => item.points.length)) throw new Error('За вибраний період у PostgreSQL ще немає збережених даних.');
  return series;
}
function graphCard(config) {
  const card = document.createElement('section'); card.className = 'panel chart-panel'; card.dataset.graphId = config.id;
  card.innerHTML = `<div class="panel-heading"><div><p class="eyebrow">Динаміка · крок ${STEP[config.step].label}</p><h2>${config.mode === 'percent' ? 'Зміна' : 'Курс'} за ${PERIOD[config.period].label}</h2></div><div class="chart-card-actions"><div class="chart-zoom-controls" role="group" aria-label="Масштаб графіка"><button class="icon-button zoom-out" type="button" title="Зменшити масштаб" aria-label="Зменшити масштаб">−</button><button class="icon-button zoom-in" type="button" title="Збільшити масштаб" aria-label="Збільшити масштаб">+</button></div><button class="button ghost reset-one" type="button">Скинути масштаб</button><button class="icon-button remove-graph" type="button" aria-label="Видалити графік">×</button></div></div><p class="chart-pan-hint">Перетягуйте графік мишею вліво, вправо, вгору або вниз. Колесо миші змінює масштаб.</p><div class="chart-wrap"><canvas aria-label="Інтерактивний графік історії курсів. Перетягування рухає графік по горизонталі та вертикалі." role="img"></canvas></div>`;
  $('#charts-container').append(card); return card;
}
function drawGraph(graph, series) {
  if (!window.Chart) throw new Error('Бібліотека графіків не завантажилась.');
  document.querySelector(`[data-graph-id="${graph.id}"] .graph-error`)?.remove();
  const datasets = series.map((item, index) => {
    const points = graph.mode === 'percent' ? percentSeries(item.points) : item.points;
    const data = points.map(point => ({ x: new Date(point.timestamp).getTime(), y: Number(point.value) }));
    const shortSeries = data.length < 3;
    const color = graph.colors[item.instrument_id] || CHART_COLORS[index % CHART_COLORS.length];
    return {
      instrumentId: item.instrument_id,
      label: item.instrument_id.split(':').slice(1).join('/').toUpperCase(),
      data,
      borderColor: color,
      backgroundColor: color,
      pointBackgroundColor: color,
      pointBorderColor: css('--surface'),
      pointBorderWidth: shortSeries ? 2 : 0,
      pointRadius: shortSeries ? 5 : 0,
      pointHoverRadius: shortSeries ? 7 : 4,
      pointHitRadius: 12,
      borderWidth: 2,
      tension: 0,
      showLine: data.length > 1,
    };
  });
  if (graph.chart) graph.chart.destroy(); const canvas = document.querySelector(`[data-graph-id="${graph.id}"] canvas`);
  const bounds = dateBounds(graph.period);
  graph.chart = new Chart(canvas, { type: 'line', data: { datasets }, options: { responsive: true, maintainAspectRatio: false, interaction: { intersect: false, mode: 'nearest' }, parsing: false, scales: { x: { type: 'linear', min: bounds.start.getTime(), max: bounds.end.getTime(), grid: { color: css('--border') }, ticks: { color: css('--muted'), stepSize: STEP[graph.step].ms, callback: value => new Intl.DateTimeFormat('uk-UA', PERIOD[graph.period].days <= 1 ? { hour: '2-digit', minute: '2-digit' } : { day: '2-digit', month: 'short', hour: '2-digit' }).format(new Date(value)) } }, y: { grid: { color: css('--border') }, ticks: { color: css('--muted'), callback: value => graph.mode === 'percent' ? `${Number(value).toFixed(2)}%` : new Intl.NumberFormat('uk-UA', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(value) } } }, plugins: { legend: { labels: { color: css('--text'), usePointStyle: true } }, tooltip: { callbacks: { title: items => new Intl.DateTimeFormat('uk-UA', { dateStyle: 'medium', timeStyle: 'medium' }).format(new Date(items[0].parsed.x)), label: context => ` ${context.dataset.label}: ${Number(context.parsed.y).toFixed(2)}${graph.mode === 'percent' ? '%' : ''}` } }, zoom: { pan: { enabled: true, mode: 'xy', threshold: 4 }, zoom: { wheel: { enabled: true, speed: .08 }, pinch: { enabled: true }, mode: 'xy' } } } } });
}
async function addGraph() {
  if (!state.selected.size) { showError('Оберіть хоча б одну валюту.'); return; }
  const instruments = [...state.selected];
  const colors = Object.fromEntries(instruments.map((id, index) => [id, state.seriesColors.get(id) || CHART_COLORS[index % CHART_COLORS.length]]));
  const graph = { id: createId(), instruments, colors, period: state.period, step: state.step, mode: state.mode, chart: null }; graphCard(graph); state.graphs.push(graph); saveSession();
  try { drawGraph(graph, await fetchGraph(graph)); wireGraph(graph); } catch (error) { removeGraph(graph.id); showError(error.message); }
}
function wireGraph(graph) {
  const card = document.querySelector(`[data-graph-id="${graph.id}"]`);
  card.querySelector('.zoom-in').addEventListener('click', () => graph.chart?.zoom(1.2));
  card.querySelector('.zoom-out').addEventListener('click', () => graph.chart?.zoom(.8));
  card.querySelector('.reset-one').addEventListener('click', () => graph.chart?.resetZoom());
  card.querySelector('.remove-graph').addEventListener('click', () => removeGraph(graph.id));
}
function removeGraph(id) { const index = state.graphs.findIndex(x => x.id === id); if (index >= 0) { state.graphs[index].chart?.destroy(); state.graphs.splice(index, 1); } document.querySelector(`[data-graph-id="${id}"]`)?.remove(); saveSession(); }
async function refreshGraphs() {
  if (graphRefreshRunning || !state.graphs.length) return;
  graphRefreshRunning = true;
  try { await Promise.all(state.graphs.map(async graph => { try { drawGraph(graph, await fetchGraph(graph)); } catch (error) { showError(`Не вдалося оновити графік: ${error.message}`); } })); }
  finally { graphRefreshRunning = false; }
}
function scheduleGraphRefresh() {
  const delay = GRAPH_REFRESH_INTERVAL - (Date.now() % GRAPH_REFRESH_INTERVAL);
  window.setTimeout(async () => {
    if (document.visibilityState === 'visible') await refreshGraphs();
    scheduleGraphRefresh();
  }, delay);
}
function resetGraphs() { state.graphs.forEach(graph => graph.chart?.destroy()); state.graphs = []; $('#charts-container').replaceChildren(); saveSession(); }

function treemapLayout(items, x = 0, y = 0, width = 100, height = 100) {
  if (!items.length) return [];
  if (items.length === 1) return [{ ...items[0], x, y, width, height }];
  const total = items.reduce((sum, item) => sum + Number(item.market_cap), 0);
  let subtotal = 0; let split = 0;
  while (split < items.length - 1 && subtotal < total / 2) { subtotal += Number(items[split].market_cap); split += 1; }
  const first = items.slice(0, split); const second = items.slice(split); const firstTotal = first.reduce((sum, item) => sum + Number(item.market_cap), 0); const ratio = total ? firstTotal / total : .5;
  if (width >= height) return [...treemapLayout(first, x, y, width * ratio, height), ...treemapLayout(second, x + width * ratio, y, width * (1 - ratio), height)];
  return [...treemapLayout(first, x, y, width, height * ratio), ...treemapLayout(second, x, y + height * ratio, width, height * (1 - ratio))];
}
function capClass(change) { return Number(change) > .01 ? 'gain' : Number(change) < -.01 ? 'loss' : 'flat'; }
function compactCap(value) { return new Intl.NumberFormat('uk-UA', { notation: 'compact', maximumFractionDigits: 2 }).format(Number(value)) + ' USD'; }
function marketTiles(items) {
  const validItems = items.filter(item => Number.isFinite(Number(item.market_cap)) && Number(item.market_cap) > 0);
  return treemapLayout(validItems.sort((a, b) => Number(b.market_cap) - Number(a.market_cap))).map(item => {
    const cap = compactCap(item.market_cap); const change = Number(item.change_percent);
    const details = `${item.name}: капіталізація ${cap}, зміна ${change >= 0 ? '+' : ''}${change.toFixed(2)}%`;
    return `<button type="button" class="market-tile ${capClass(change)}" style="left:${item.x}%;top:${item.y}%;width:${item.width}%;height:${item.height}%" title="${escapeHTML(details)}" aria-label="${escapeHTML(details)}"><span class="market-tile-symbol">${escapeHTML(item.symbol)}</span><span class="market-tile-value">${escapeHTML(cap)}</span><span class="market-tile-change">${change >= 0 ? '+' : ''}${change.toFixed(2)}%</span></button>`;
  }).join('');
}
function marketMapCard(map) {
  const card = document.createElement('section'); card.className = 'panel market-map-card'; card.dataset.marketMapId = map.id;
  card.innerHTML = `<div class="panel-heading"><div><p class="eyebrow">CoinGecko</p><h2>Капіталізація: ${MARKET_PERIOD_LABELS[map.period]}</h2></div><button class="icon-button remove-market-map" type="button" aria-label="Видалити карту">×</button></div><div class="market-map-surface">${marketTiles(map.items)}</div><div class="market-legend"><span class="gain">Зросла</span><span class="loss">Впала</span><span class="flat">Без суттєвої зміни</span></div>`;
  $('#market-maps-container').append(card); card.querySelector('.remove-market-map').addEventListener('click', () => removeMarketMap(map.id));
}
async function addMarketMap() {
  const button = $('#add-market-map'); button.disabled = true;
  try { const data = await api(`/market-map?period=${state.marketPeriod}`); const map = { id: createId(), period: state.marketPeriod, items: data.items }; state.marketMaps.push(map); marketMapCard(map); }
  catch (error) { showError(error.message); } finally { button.disabled = false; }
}
function removeMarketMap(id) { state.marketMaps = state.marketMaps.filter(map => map.id !== id); document.querySelector(`[data-market-map-id="${id}"]`)?.remove(); }
function resetMarketMaps() { state.marketMaps = []; $('#market-maps-container').replaceChildren(); }
async function refreshMarketMaps() {
  const snapshots = [...state.marketMaps];
  for (const map of snapshots) { try { const data = await api(`/market-map?period=${map.period}`); map.items = data.items; const old = document.querySelector(`[data-market-map-id="${map.id}"]`); old?.remove(); marketMapCard(map); } catch (error) { showError(`Не вдалося оновити карту: ${error.message}`); } }
}

function escapeHTML(value) { return String(value ?? '').replace(/[&<>'"]/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' })[char]); }
function pdfRateCard(rate) {
  const hour = rate.change_1h_percent == null ? '—' : `${Number(rate.change_1h_percent).toFixed(2)}%`;
  const day = rate.change_24h_percent == null ? '—' : `${Number(rate.change_24h_percent).toFixed(2)}%`;
  return `<article class="pdf-rate-card"><h3>${escapeHTML(rate.name)} · ${escapeHTML(rate.base)}/${escapeHTML(rate.quote)}</h3><dl><dt>Поточний курс</dt><dd><strong>${escapeHTML(formatMoney(rate.price, rate.quote))}</strong></dd><dt>Зміна за 1 годину</dt><dd>${hour}</dd><dt>Зміна за 1 день</dt><dd>${day}</dd><dt>Джерело</dt><dd>${escapeHTML(rate.source)}</dd><dt>Час джерела</dt><dd>${new Intl.DateTimeFormat('uk-UA', { dateStyle: 'medium', timeStyle: 'medium' }).format(new Date(rate.source_timestamp))}</dd></dl></article>`;
}
function buildPDFReport() {
  const cards = [state.primary, ...state.comparisons].filter(Boolean);
  const readyGraphs = state.graphs.filter(graph => graph.chart);
  const generated = new Intl.DateTimeFormat('uk-UA', { dateStyle: 'full', timeStyle: 'medium' }).format(new Date());
  const siteAddress = window.location.host;
  const cardContent = cards.length ? `<div class="pdf-card-grid">${cards.map(pdfRateCard).join('')}</div>` : '<p>Інформація відсутня.</p>';
  const graphContent = readyGraphs.length ? readyGraphs.map((graph, index) => `<article class="pdf-chart"><h3>Графік ${index + 1}: ${graph.mode === 'percent' ? 'зміна' : 'курс'} за ${PERIOD[graph.period].label}</h3><p>Крок: ${STEP[graph.step].label}. ${graph.instruments.map(id => escapeHTML(id.split(':').slice(1).join('/').toUpperCase())).join(', ')}</p><img src="${graph.chart.toBase64Image('image/png', 1)}" alt="Графік ${index + 1}"></article>`).join('') : '<p>Інформація відсутня.</p>';
  const marketContent = state.marketMaps.length ? state.marketMaps.map((map, index) => `<article class="pdf-market"><h3>Карта ${index + 1}: зміна за ${MARKET_PERIOD_LABELS[map.period]}</h3><div class="pdf-market-surface">${marketTiles(map.items)}</div></article>`).join('') : '<p>Інформація відсутня.</p>';
  $('#pdf-report').innerHTML = `<header><p class="eyebrow">Rateboard · ${escapeHTML(siteAddress)}</p><h1>Дані на сьогоднішній день</h1><p class="pdf-generated">Сформовано: ${generated}</p></header><section><h2>Детальна інформація з карток</h2>${cardContent}</section><section><h2>Карти капіталізації</h2>${marketContent}</section><section><h2>Графіки</h2>${graphContent}</section><footer class="pdf-report-footer"><span>© Rateboard 2026</span><span>${escapeHTML(siteAddress)}</span></footer>`;
}
function exportPDF() { buildPDFReport(); window.print(); }

function initEvents() {
  document.querySelectorAll('.tab').forEach(tab => tab.addEventListener('click', () => { state.activeTab = tab.dataset.tab; document.querySelectorAll('.tab').forEach(item => { const active = item === tab; item.classList.toggle('active', active); item.setAttribute('aria-selected', active); }); $('#overview-panel').hidden = tab.dataset.tab !== 'overview'; $('#history-panel').hidden = tab.dataset.tab !== 'history'; $('#market-map-panel').hidden = tab.dataset.tab !== 'market-map'; saveSession(); }));
  $('#refresh-button').addEventListener('click', refreshEverything); $('#add-compare').addEventListener('click', () => { renderPicker(); $('#compare-dialog').showModal(); }); $('#compare-search').addEventListener('input', event => renderPicker(event.target.value));
  $('#instrument-trigger').addEventListener('click', event => { const picker = $('#instrument-picker'); picker.hidden = !picker.hidden; event.currentTarget.setAttribute('aria-expanded', !picker.hidden); if (!picker.hidden) $('#instrument-search').focus(); }); $('#instrument-search').addEventListener('input', event => renderInstrumentOptions(event.target.value));
  document.addEventListener('click', event => { if (!event.target.closest('.control.wide')) { $('#instrument-picker').hidden = true; $('#instrument-trigger').setAttribute('aria-expanded', 'false'); } });
  $('#period-buttons').addEventListener('click', event => { if (!event.target.dataset.period) return; state.period = event.target.dataset.period; [...event.currentTarget.children].forEach(x => x.classList.toggle('active', x === event.target)); saveSession(); });
  $('#step-buttons').addEventListener('click', event => { if (!event.target.dataset.step) return; state.step = event.target.dataset.step; [...event.currentTarget.children].forEach(x => x.classList.toggle('active', x === event.target)); saveSession(); });
  $('#mode-buttons').addEventListener('click', event => { if (!event.target.dataset.mode) return; state.mode = event.target.dataset.mode; [...event.currentTarget.children].forEach(x => x.classList.toggle('active', x === event.target)); saveSession(); });
  $('#load-chart').addEventListener('click', addGraph); $('#refresh-charts').addEventListener('click', refreshGraphs); $('#reset-charts').addEventListener('click', resetGraphs); $('#export-pdf-global').addEventListener('click', exportPDF);
  $('#market-period-buttons').addEventListener('click', event => { if (!event.target.dataset.period) return; state.marketPeriod = event.target.dataset.period; [...event.currentTarget.children].forEach(item => item.classList.toggle('active', item === event.target)); saveSession(); }); $('#add-market-map').addEventListener('click', addMarketMap); $('#refresh-market-maps').addEventListener('click', refreshMarketMaps); $('#reset-market-maps').addEventListener('click', resetMarketMaps);
}

initTheme(); initEvents(); scheduleGraphRefresh();
restoreSession().then(loadOverview).then(loaded => {
  sessionHydrated = true;
  if (loaded) saveSession();
});
