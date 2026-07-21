const citySwitcher = document.querySelector("#city-switcher");
const refreshButton = document.querySelector("#refresh-button");
const pageMessage = document.querySelector("#page-message");

const currentSection = document.querySelector("#current-section");
const currentCityHeading = document.querySelector(
    "#current-city-heading"
);
const locationDescription = document.querySelector(
    "#location-description"
);
const lastUpdated = document.querySelector("#last-updated");
const primaryAqiValue = document.querySelector(
    "#primary-aqi-value"
);
const primaryAqiClassification = document.querySelector(
    "#primary-aqi-classification"
);
const latestMetrics = document.querySelector("#latest-metrics");

const historySection = document.querySelector("#history-section");
const historyHeading = document.querySelector("#history-heading");
const metricSelect = document.querySelector("#metric-select");
const periodButtons = document.querySelectorAll(".period-button");
const chartMessage = document.querySelector("#chart-message");
const historyChart = document.querySelector("#history-chart");
const chartRangeDescription = document.querySelector(
    "#chart-range-description"
);
const chartPointCount = document.querySelector(
    "#chart-point-count"
);

const emptyState = document.querySelector("#empty-state");


const metricDefinitions = {
    european_aqi: {
        label: "European AQI",
        unit: "",
    },
    us_aqi: {
        label: "US AQI",
        unit: "",
    },
    pm2_5: {
        label: "PM2.5",
        unit: "μg/m³",
    },
    pm10: {
        label: "PM10",
        unit: "μg/m³",
    },
    nitrogen_dioxide: {
        label: "Nitrogen dioxide",
        unit: "μg/m³",
    },
    ozone: {
        label: "Ozone",
        unit: "μg/m³",
    },
    carbon_monoxide: {
        label: "Carbon monoxide",
        unit: "μg/m³",
    },
    uv_index: {
        label: "UV index",
        unit: "",
    },
};


let cities = [];
let selectedCityCode = null;
let selectedHours = 24;
let dashboardData = null;
let isLoading = false;


refreshButton.addEventListener("click", async () => {
    if (!selectedCityCode || isLoading) {
        return;
    }

    await loadDashboard();
});


periodButtons.forEach((button) => {
    button.addEventListener("click", async () => {
        const hours = Number(button.dataset.hours);

        if (hours === selectedHours || isLoading) {
            return;
        }

        selectedHours = hours;

        periodButtons.forEach((item) => {
            item.classList.toggle(
                "active",
                Number(item.dataset.hours) === selectedHours
            );
        });

        await loadDashboard();
    });
});


metricSelect.addEventListener("change", () => {
    if (!dashboardData) {
        return;
    }

    renderChart(
        dashboardData.history,
        metricSelect.value
    );
});


async function initialize() {
    try {
        const response = await fetch("/api/cities");
        const payload = await readJsonResponse(response);

        if (!response.ok) {
            throw new Error(extractErrorMessage(payload));
        }

        if (!Array.isArray(payload) || payload.length === 0) {
            throw new Error(
                "No active cities are configured in the Backend Service."
            );
        }

        cities = payload;
        renderCitySwitcher();

        selectedCityCode = cities[0].code;

        updateActiveCityButton();

        await loadDashboard();

    } catch (error) {
        showMessage(
            pageMessage,
            error.message || "Could not load configured cities.",
            "error"
        );
    }
}


function renderCitySwitcher() {
    const buttons = cities.map((city) => {
        const button = document.createElement("button");

        button.type = "button";
        button.className = "city-button";
        button.dataset.cityCode = city.code;
        button.textContent = city.name;
        button.setAttribute("role", "tab");
        button.setAttribute("aria-selected", "false");

        button.addEventListener("click", async () => {
            if (
                city.code === selectedCityCode
                || isLoading
            ) {
                return;
            }

            selectedCityCode = city.code;
            updateActiveCityButton();

            await loadDashboard();
        });

        return button;
    });

    citySwitcher.replaceChildren(...buttons);
}


function updateActiveCityButton() {
    citySwitcher
        .querySelectorAll(".city-button")
        .forEach((button) => {
            const isActive =
                button.dataset.cityCode === selectedCityCode;

            button.classList.toggle("active", isActive);
            button.setAttribute(
                "aria-selected",
                String(isActive)
            );
        });
}


async function loadDashboard() {
    setLoading(true);

    showMessage(
        pageMessage,
        "Loading stored air-quality data..."
    );

    try {
        const query = new URLSearchParams({
            city: selectedCityCode,
            hours: String(selectedHours),
        });

        const response = await fetch(
            `/api/dashboard?${query.toString()}`
        );

        const payload = await readJsonResponse(response);

        if (!response.ok) {
            throw new Error(extractErrorMessage(payload));
        }

        dashboardData = payload;

        renderDashboard(payload);

        showMessage(
            pageMessage,
            "Dashboard data loaded.",
            "success"
        );

    } catch (error) {
        dashboardData = null;

        hideDashboard();

        showMessage(
            pageMessage,
            error.message || "Could not load dashboard data.",
            "error"
        );

    } finally {
        setLoading(false);
    }
}


function renderDashboard(payload) {
    const city = payload.city;
    const latest = payload.latest;
    const history = Array.isArray(payload.history)
        ? payload.history
        : [];

    currentCityHeading.textContent =
        `Current air quality in ${city.name}`;

    locationDescription.textContent = [
        city.country,
        city.timezone,
    ].filter(Boolean).join(" · ");

    historyHeading.textContent =
        `${city.name} air-quality trend`;

    if (!latest) {
        currentSection.classList.add("hidden");
        historySection.classList.add("hidden");
        emptyState.classList.remove("hidden");

        return;
    }

    emptyState.classList.add("hidden");
    currentSection.classList.remove("hidden");
    historySection.classList.remove("hidden");

    lastUpdated.textContent = formatDateTime(
        latest.observed_at
    );

    primaryAqiValue.textContent = formatValue(
        latest.european_aqi
    );

    primaryAqiClassification.textContent =
        classifyEuropeanAqi(latest.european_aqi);

    renderLatestMetrics(latest);
    renderChart(history, metricSelect.value);
}


function renderLatestMetrics(latest) {
    const metrics = [
        "us_aqi",
        "pm2_5",
        "pm10",
        "nitrogen_dioxide",
        "ozone",
        "carbon_monoxide",
        "uv_index",
    ];

    const cards = metrics.map((metricName) => {
        const definition = metricDefinitions[metricName];

        const card = document.createElement("article");
        card.className = "metric-card";

        const label = document.createElement("div");
        label.className = "metric-label";
        label.textContent = definition.label;

        const valueWrapper = document.createElement("div");
        valueWrapper.className = "metric-card-value";

        const value = document.createElement("span");
        value.textContent = formatValue(
            latest[metricName]
        );

        valueWrapper.appendChild(value);

        if (definition.unit) {
            const unit = document.createElement("span");
            unit.className = "metric-unit";
            unit.textContent = definition.unit;

            valueWrapper.appendChild(unit);
        }

        card.append(label, valueWrapper);

        return card;
    });

    latestMetrics.replaceChildren(...cards);
}


function renderChart(history, metricName) {
    clearSvg(historyChart);

    const definition = metricDefinitions[metricName];

    const points = history
        .filter((measurement) => {
            return measurement[metricName] !== null
                && measurement[metricName] !== undefined;
        })
        .map((measurement) => {
            return {
                time: new Date(measurement.observed_at),
                value: Number(measurement[metricName]),
            };
        })
        .filter((point) => {
            return (
                !Number.isNaN(point.time.getTime())
                && Number.isFinite(point.value)
            );
        });

    updateChartDescription(
        definition,
        points
    );

    if (points.length === 0) {
        showMessage(
            chartMessage,
            `No ${definition.label} measurements are available `
            + `for the selected period.`
        );

        return;
    }

    showMessage(chartMessage, "");

    const width = 1000;
    const height = 420;

    const margin = {
        top: 32,
        right: 34,
        bottom: 62,
        left: 78,
    };

    const plotWidth =
        width - margin.left - margin.right;

    const plotHeight =
        height - margin.top - margin.bottom;

    const values = points.map((point) => point.value);

    let minimumValue = Math.min(...values);
    let maximumValue = Math.max(...values);

    if (minimumValue === maximumValue) {
        const padding = minimumValue === 0
            ? 1
            : Math.abs(minimumValue) * 0.1;

        minimumValue -= padding;
        maximumValue += padding;
    } else {
        const padding =
            (maximumValue - minimumValue) * 0.12;

        minimumValue = Math.max(
            0,
            minimumValue - padding
        );

        maximumValue += padding;
    }

    const minimumTime = points[0].time.getTime();
    const maximumTime = points.at(-1).time.getTime();

    const timeRange = Math.max(
        maximumTime - minimumTime,
        1
    );

    const valueRange = Math.max(
        maximumValue - minimumValue,
        1
    );

    const xScale = (time) => {
        return margin.left
            + (
                (time.getTime() - minimumTime)
                / timeRange
            ) * plotWidth;
    };

    const yScale = (value) => {
        return margin.top
            + (
                1
                - (
                    (value - minimumValue)
                    / valueRange
                )
            ) * plotHeight;
    };

    drawGrid({
        svg: historyChart,
        width,
        height,
        margin,
        plotWidth,
        plotHeight,
        minimumValue,
        maximumValue,
        minimumTime,
        maximumTime,
        definition,
    });

    const scaledPoints = points.map((point) => {
        return {
            ...point,
            x: xScale(point.time),
            y: yScale(point.value),
        };
    });

    drawArea(
        historyChart,
        scaledPoints,
        margin.top + plotHeight
    );

    drawLine(historyChart, scaledPoints);
    drawPoints(historyChart, scaledPoints, definition);
}


function drawGrid({
    svg,
    margin,
    plotWidth,
    plotHeight,
    minimumValue,
    maximumValue,
    minimumTime,
    maximumTime,
    definition,
}) {
    const horizontalLines = 5;
    const verticalLines = 5;

    for (
        let index = 0;
        index <= horizontalLines;
        index += 1
    ) {
        const ratio = index / horizontalLines;
        const y = margin.top + ratio * plotHeight;

        const value =
            maximumValue
            - ratio * (maximumValue - minimumValue);

        svg.appendChild(
            createSvgElement("line", {
                x1: margin.left,
                y1: y,
                x2: margin.left + plotWidth,
                y2: y,
                class: "chart-grid-line",
            })
        );

        const label = createSvgElement("text", {
            x: margin.left - 16,
            y: y + 7,
            "text-anchor": "end",
            class: "chart-axis-label",
        });

        label.textContent = formatAxisValue(
            value,
            definition.unit
        );

        svg.appendChild(label);
    }

    for (
        let index = 0;
        index <= verticalLines;
        index += 1
    ) {
        const ratio = index / verticalLines;
        const x = margin.left + ratio * plotWidth;

        const timestamp =
            minimumTime
            + ratio * (maximumTime - minimumTime);

        svg.appendChild(
            createSvgElement("line", {
                x1: x,
                y1: margin.top,
                x2: x,
                y2: margin.top + plotHeight,
                class: "chart-grid-line",
            })
        );

        const label = createSvgElement("text", {
            x,
            y: margin.top + plotHeight + 35,
            "text-anchor": "middle",
            class: "chart-axis-label",
        });

        label.textContent = formatChartTime(
            new Date(timestamp)
        );

        svg.appendChild(label);
    }
}


function drawLine(svg, points) {
    const path = createSvgElement("path", {
        d: createLinePath(points),
        class: "chart-line",
    });

    svg.appendChild(path);
}


function drawArea(svg, points, baselineY) {
    if (points.length === 0) {
        return;
    }

    const linePath = createLinePath(points);

    const firstPoint = points[0];
    const lastPoint = points.at(-1);

    const path = createSvgElement("path", {
        d:
            `${linePath} `
            + `L ${lastPoint.x} ${baselineY} `
            + `L ${firstPoint.x} ${baselineY} Z`,
        class: "chart-area",
    });

    svg.appendChild(path);
}


function drawPoints(svg, points, definition) {
    points.forEach((point) => {
        const circle = createSvgElement("circle", {
            cx: point.x,
            cy: point.y,
            r: 6,
            class: "chart-point",
        });

        const title = createSvgElement("title");

        title.textContent =
            `${formatDateTime(point.time)}: `
            + `${formatValue(point.value)}`
            + (
                definition.unit
                    ? ` ${definition.unit}`
                    : ""
            );

        circle.appendChild(title);
        svg.appendChild(circle);
    });
}


function createLinePath(points) {
    return points
        .map((point, index) => {
            const command = index === 0 ? "M" : "L";

            return `${command} ${point.x} ${point.y}`;
        })
        .join(" ");
}


function updateChartDescription(
    definition,
    points
) {
    const title = historyChart.querySelector("title");
    const description = historyChart.querySelector("desc");

    if (title) {
        title.textContent =
            `${definition.label} historical chart`;
    }

    if (description) {
        description.textContent =
            `${definition.label} values for the last `
            + `${selectedHours} hours.`;
    }

    chartPointCount.textContent =
        `${points.length} measurement`
        + `${points.length === 1 ? "" : "s"}`;

    if (points.length > 0) {
        chartRangeDescription.textContent =
            `${formatDateTime(points[0].time)} — `
            + `${formatDateTime(points.at(-1).time)}`;
    } else {
        chartRangeDescription.textContent =
            `Last ${selectedHours} hours`;
    }
}


function hideDashboard() {
    currentSection.classList.add("hidden");
    historySection.classList.add("hidden");
    emptyState.classList.add("hidden");
}


function setLoading(loading) {
    isLoading = loading;

    refreshButton.disabled = loading
        || !selectedCityCode;

    refreshButton.textContent = loading
        ? "Reloading..."
        : "Reload dashboard";

    citySwitcher
        .querySelectorAll("button")
        .forEach((button) => {
            button.disabled = loading;
        });

    periodButtons.forEach((button) => {
        button.disabled = loading;
    });

    metricSelect.disabled = loading;
}


function showMessage(element, message, type = "") {
    element.textContent = message;
    element.className = "status-message";

    if (type) {
        element.classList.add(type);
    }
}


function classifyEuropeanAqi(value) {
    if (value === null || value === undefined) {
        return "No classification available";
    }

    if (value <= 20) {
        return "Good";
    }

    if (value <= 40) {
        return "Fair";
    }

    if (value <= 60) {
        return "Moderate";
    }

    if (value <= 80) {
        return "Poor";
    }

    if (value <= 100) {
        return "Very poor";
    }

    return "Extremely poor";
}


function formatValue(value) {
    if (value === null || value === undefined) {
        return "N/A";
    }

    if (typeof value === "number") {
        return Number.isInteger(value)
            ? String(value)
            : value.toFixed(1);
    }

    return String(value);
}


function formatAxisValue(value, unit) {
    const formatted = Math.abs(value) >= 100
        ? value.toFixed(0)
        : value.toFixed(1);

    return unit
        ? `${formatted}`
        : formatted;
}


function formatDateTime(value) {
    if (!value) {
        return "Unknown";
    }

    const date = value instanceof Date
        ? value
        : new Date(value);

    if (Number.isNaN(date.getTime())) {
        return String(value);
    }

    return new Intl.DateTimeFormat(
        undefined,
        {
            dateStyle: "medium",
            timeStyle: "short",
        }
    ).format(date);
}


function formatChartTime(date) {
    return new Intl.DateTimeFormat(
        undefined,
        {
            hour: "2-digit",
            minute: "2-digit",
        }
    ).format(date);
}


function extractErrorMessage(payload) {
    if (
        payload
        && typeof payload === "object"
        && typeof payload.detail === "string"
    ) {
        return payload.detail;
    }

    return "The request failed.";
}


async function readJsonResponse(response) {
    try {
        return await response.json();
    } catch {
        return {};
    }
}


function createSvgElement(tagName, attributes = {}) {
    const element = document.createElementNS(
        "http://www.w3.org/2000/svg",
        tagName
    );

    Object.entries(attributes).forEach(([name, value]) => {
        element.setAttribute(name, String(value));
    });

    return element;
}


function clearSvg(svg) {
    const title = svg.querySelector("title");
    const description = svg.querySelector("desc");

    svg.replaceChildren();

    if (title) {
        svg.appendChild(title);
    }

    if (description) {
        svg.appendChild(description);
    }
}


initialize();