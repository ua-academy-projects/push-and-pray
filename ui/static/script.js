const state = {
    preferences: null,
    cities: [],
    chartData: null,
    refreshTimer: null,
};

const elements = {
    city: document.getElementById("city-select"),
    metric: document.getElementById("metric-select"),
    period: document.getElementById("period-select"),
    reload: document.getElementById("reload-button"),
    autoRefresh: document.getElementById("auto-refresh"),
    compactMode: document.getElementById("compact-mode"),
    message: document.getElementById("message"),
    status: document.getElementById("system-status"),
    canvas: document.getElementById("weather-chart"),
    chartEmpty: document.getElementById("chart-empty"),
    historyBody: document.getElementById("history-body"),
    historyEmpty: document.getElementById("history-empty"),
};

async function requestJson(url, options = {}) {
    const response = await fetch(url, {
        headers: { "Content-Type": "application/json" },
        ...options,
    });
    let data;
    try {
        data = await response.json();
    } catch (_error) {
        data = { error: "Не вдалося отримати дані" };
    }
    if (!response.ok) {
        const error = new Error(data.error || `HTTP ${response.status}`);
        error.status = response.status;
        error.data = data;
        throw error;
    }
    return data;
}

function showMessage(text, type = "error") {
    elements.message.textContent = text;
    elements.message.className = `message ${type}`;
}

function hideMessage() {
    elements.message.textContent = "";
    elements.message.className = "message hidden";
}

function number(value, digits = 1) {
    const parsed = Number(value);
    if (!Number.isFinite(parsed)) return "—";
    return parsed.toLocaleString("uk-UA", {
        maximumFractionDigits: digits,
        minimumFractionDigits: Number.isInteger(parsed) ? 0 : digits,
    });
}

function dateTime(value) {
    if (!value) return "—";
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return String(value);
    return date.toLocaleString("uk-UA", {
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
        hour: "2-digit",
        minute: "2-digit",
    });
}

function iconForCode(code) {
    const value = Number(code);
    if (value === 0) return "☀️";
    if ([1, 2].includes(value)) return "🌤️";
    if (value === 3) return "☁️";
    if ([45, 48].includes(value)) return "🌫️";
    if ([71, 73, 75, 77, 85, 86].includes(value)) return "❄️";
    if ([95, 96, 99].includes(value)) return "⛈️";
    if ([51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82].includes(value)) return "🌧️";
    return "🌡️";
}

async function savePreferences(changes = {}) {
    state.preferences = { ...state.preferences, ...changes };
    const data = await requestJson("/api/preferences", {
        method: "POST",
        body: JSON.stringify(state.preferences),
    });
    state.preferences = data.preferences;
}

function populateCities() {
    elements.city.innerHTML = "";
    for (const city of state.cities) {
        const option = document.createElement("option");
        option.value = String(city.id);
        option.textContent = `${city.name} — ${city.oblast}`;
        elements.city.appendChild(option);
    }

    let selected = state.preferences.city_id;
    if (!state.cities.some((city) => city.id === selected)) {
        const kyiv = state.cities.find((city) => city.name_en === "Kyiv");
        selected = kyiv ? kyiv.id : state.cities[0]?.id;
        state.preferences.city_id = selected || null;
    }

    if (selected) elements.city.value = String(selected);
    elements.city.disabled = state.cities.length === 0;
}

function applyPreferences() {
    elements.metric.value = state.preferences.metric;
    elements.period.value = state.preferences.period;
    elements.autoRefresh.checked = state.preferences.auto_refresh;
    elements.compactMode.checked = state.preferences.compact_mode;
    document.body.classList.toggle("compact", state.preferences.compact_mode);
    configureAutoRefresh();
}

async function loadHealth() {
    try {
        const health = await requestJson("/api/health");
        elements.status.className = "system-status healthy";
        elements.status.lastElementChild.textContent = "Онлайн";
    } catch (_error) {
        elements.status.className = "system-status error";
        elements.status.lastElementChild.textContent = "Тимчасово недоступно";
    }
}

function selectedCityId() {
    return Number(elements.city.value || state.preferences.city_id);
}

async function loadDashboard(showSuccess = false) {
    const cityId = selectedCityId();
    if (!cityId) {
        showMessage("Наразі немає доступних міст.");
        return;
    }

    elements.reload.disabled = true;
    elements.reload.textContent = "Оновлення...";
    hideMessage();

    const currentPromise = loadCurrentWeather(cityId);
    const chartPromise = loadChart(cityId);
    const historyPromise = loadHistory(cityId);
    await Promise.allSettled([currentPromise, chartPromise, historyPromise]);
    await loadHealth();

    elements.reload.disabled = false;
    elements.reload.textContent = "Оновити дані";
    if (showSuccess) {
        showMessage("Дані оновлено.", "success");
    }
}

async function loadCurrentWeather(cityId) {
    try {
        const data = await requestJson(`/api/weather?city_id=${encodeURIComponent(cityId)}`);
        renderCurrent(data.weather);
    } catch (error) {
        clearCurrent();
        if (error.status === 404) {
            showMessage(error.message, "error");
            return;
        }
        showMessage("Не вдалося завантажити поточну погоду.", "error");
    }
}

function renderCurrent(weather) {
    document.getElementById("city-name").textContent = weather.city;
    document.getElementById("oblast-name").textContent = weather.oblast;
    document.getElementById("weather-icon").textContent = iconForCode(weather.weather_code);
    document.getElementById("temperature").textContent = number(weather.temperature);
    document.getElementById("weather-description").textContent = weather.weather_description || "Немає опису";
    document.getElementById("feels-like").textContent = number(weather.feels_like);
    document.getElementById("humidity").textContent = number(weather.humidity, 0);
    document.getElementById("pressure").textContent = number(weather.pressure);
    document.getElementById("wind-speed").textContent = number(weather.wind_speed);
    document.getElementById("observed-at").textContent = dateTime(weather.observed_at);
    document.getElementById("coordinates").textContent = `${number(weather.latitude, 4)}, ${number(weather.longitude, 4)}`;
}

function clearCurrent() {
    const ids = ["temperature", "feels-like", "humidity", "pressure", "wind-speed", "observed-at", "coordinates"];
    for (const id of ids) document.getElementById(id).textContent = "—";
    document.getElementById("weather-icon").textContent = "◌";
    document.getElementById("weather-description").textContent = "Наразі даних немає.";
}

async function loadChart(cityId) {
    try {
        const params = new URLSearchParams({
            city_id: String(cityId),
            metric: elements.metric.value,
            period: elements.period.value,
        });
        const data = await requestJson(`/api/chart?${params.toString()}`);
        state.chartData = data;
        document.getElementById("chart-title").textContent = `${data.metric_label}, ${data.unit}`;
        document.getElementById("chart-count").textContent = `${data.count} точок`;
        drawChart();
    } catch (error) {
        state.chartData = null;
        drawChart();
        showMessage("Не вдалося завантажити графік.", "error");
    }
}

function drawChart() {
    const canvas = elements.canvas;
    const rect = canvas.getBoundingClientRect();
    const width = Math.max(320, rect.width);
    const height = Math.max(220, rect.height || 320);
    const ratio = window.devicePixelRatio || 1;
    canvas.width = Math.round(width * ratio);
    canvas.height = Math.round(height * ratio);

    const context = canvas.getContext("2d");
    context.setTransform(ratio, 0, 0, ratio, 0, 0);
    context.clearRect(0, 0, width, height);

    const data = state.chartData;
    const values = data?.values || [];
    const labels = data?.labels || [];
    elements.chartEmpty.classList.toggle("hidden", values.length > 0);
    if (values.length === 0) return;

    const styles = getComputedStyle(document.documentElement);
    const accent = styles.getPropertyValue("--accent").trim();
    const muted = styles.getPropertyValue("--muted").trim();
    const border = styles.getPropertyValue("--border").trim();
    const padding = { left: 58, right: 18, top: 18, bottom: 42 };
    const chartWidth = width - padding.left - padding.right;
    const chartHeight = height - padding.top - padding.bottom;

    let min = Math.min(...values.map(Number));
    let max = Math.max(...values.map(Number));
    if (min === max) {
        min -= 1;
        max += 1;
    }
    const extra = (max - min) * 0.08;
    min -= extra;
    max += extra;

    context.font = "12px system-ui";
    context.lineWidth = 1;
    context.textBaseline = "middle";

    for (let i = 0; i <= 5; i += 1) {
        const y = padding.top + (chartHeight * i) / 5;
        const value = max - ((max - min) * i) / 5;
        context.strokeStyle = border;
        context.beginPath();
        context.moveTo(padding.left, y);
        context.lineTo(width - padding.right, y);
        context.stroke();
        context.fillStyle = muted;
        context.textAlign = "right";
        context.fillText(number(value), padding.left - 9, y);
    }

    const xFor = (index) => padding.left + (values.length === 1 ? chartWidth / 2 : (chartWidth * index) / (values.length - 1));
    const yFor = (value) => padding.top + ((max - Number(value)) / (max - min)) * chartHeight;

    context.strokeStyle = accent;
    context.lineWidth = 2.5;
    context.lineJoin = "round";
    context.lineCap = "round";
    context.beginPath();
    values.forEach((value, index) => {
        const x = xFor(index);
        const y = yFor(value);
        if (index === 0) context.moveTo(x, y);
        else context.lineTo(x, y);
    });
    context.stroke();

    if (values.length <= 80) {
        context.fillStyle = accent;
        values.forEach((value, index) => {
            context.beginPath();
            context.arc(xFor(index), yFor(value), 2.5, 0, Math.PI * 2);
            context.fill();
        });
    }

    const tickIndexes = [...new Set([0, Math.floor((values.length - 1) / 2), values.length - 1])];
    context.fillStyle = muted;
    context.textAlign = "center";
    context.textBaseline = "top";
    for (const index of tickIndexes) {
        const date = new Date(labels[index]);
        const label = Number.isNaN(date.getTime())
            ? labels[index]
            : date.toLocaleString("uk-UA", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });
        context.fillText(label, xFor(index), height - padding.bottom + 12);
    }
}

async function loadHistory(cityId) {
    try {
        const data = await requestJson(`/api/history?city_id=${encodeURIComponent(cityId)}&limit=50`);
        renderHistory(data.items);
    } catch (error) {
        renderHistory([]);
        showMessage("Не вдалося завантажити історію.", "error");
    }
}

function renderHistory(items) {
    elements.historyBody.innerHTML = "";
    elements.historyEmpty.classList.toggle("hidden", items.length > 0);
    document.getElementById("history-count").textContent = `${items.length} записів`;

    for (const item of items) {
        const row = document.createElement("tr");
        const values = [
            dateTime(item.observed_at),
            `${number(item.temperature)} °C`,
            `${number(item.feels_like)} °C`,
            `${number(item.humidity, 0)} %`,
            `${number(item.pressure)} hPa`,
            `${number(item.wind_speed)} км/год`,
        ];
        for (const value of values) {
            const cell = document.createElement("td");
            cell.textContent = value;
            row.appendChild(cell);
        }
        elements.historyBody.appendChild(row);
    }
}

function configureAutoRefresh() {
    if (state.refreshTimer) clearInterval(state.refreshTimer);
    state.refreshTimer = null;
    if (state.preferences?.auto_refresh) {
        state.refreshTimer = setInterval(() => loadDashboard(false), 60 * 1000);
    }
}

async function initialize() {
    try {
        const [preferencesData, citiesData] = await Promise.all([
            requestJson("/api/preferences"),
            requestJson("/api/cities"),
        ]);
        state.preferences = preferencesData.preferences;
        state.cities = citiesData.items || [];
        populateCities();
        applyPreferences();
        await savePreferences({ city_id: selectedCityId() || null });
        await loadDashboard(false);
    } catch (error) {
        showMessage("Не вдалося завантажити сторінку. Спробуйте ще раз пізніше.");
        elements.status.className = "system-status error";
        elements.status.lastElementChild.textContent = "Система недоступна";
    }
}

elements.reload.addEventListener("click", () => loadDashboard(true));

elements.city.addEventListener("change", async () => {
    await savePreferences({ city_id: selectedCityId() });
    await loadDashboard(false);
});

elements.metric.addEventListener("change", async () => {
    await savePreferences({ metric: elements.metric.value });
    await loadChart(selectedCityId());
});

elements.period.addEventListener("change", async () => {
    await savePreferences({ period: elements.period.value });
    await loadChart(selectedCityId());
});

elements.autoRefresh.addEventListener("change", async () => {
    await savePreferences({ auto_refresh: elements.autoRefresh.checked });
    configureAutoRefresh();
});

elements.compactMode.addEventListener("change", async () => {
    await savePreferences({ compact_mode: elements.compactMode.checked });
    document.body.classList.toggle("compact", elements.compactMode.checked);
    drawChart();
});

let resizeTimer;
window.addEventListener("resize", () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(drawChart, 120);
});

initialize();
