const AUTO_REFRESH_INTERVAL_MS = 60_000;
const WEATHER_TIME_ZONE = "Europe/Kyiv";

// ── DOM references ────────────────────────────────────────────────────────

const weatherResult =
    document.getElementById("weather-result");

// Forecast chart
const forecastSection =
    document.getElementById("forecast-section");

const forecastStatus =
    document.getElementById("forecast-status");

const forecastChartEmpty =
    document.getElementById("forecast-chart-empty");

const forecastChartContainer =
    document.getElementById("forecast-chart-container");

const forecastTemperatureChart =
    document.getElementById("forecast-temperature-chart");

// History chart
const historySection =
    document.getElementById("history-section");

const historyStatus =
    document.getElementById("history-status");

const historyChartEmpty =
    document.getElementById("history-chart-empty");

const historyChartContainer =
    document.getElementById("history-chart-container");

const historyTemperatureChart =
    document.getElementById("history-temperature-chart");

// Measurements table
const historyResult =
    document.getElementById("history-result");

// Toggle buttons
const historyToggle24 =
    document.getElementById("history-toggle-24");

const historyToggle168 =
    document.getElementById("history-toggle-168");

// ── State ─────────────────────────────────────────────────────────────────

let isLoading = false;
let forecastAbortController = null;
let historyAbortController = null;
let currentHistoryHours = 24;


// ── String utilities ──────────────────────────────────────────────────────

function escapeHtml(value) {
    return String(value)
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;")
        .replaceAll("'", "&#039;");
}


function valueOrDash(value) {
    if (
        value === null ||
        value === undefined ||
        value === ""
    ) {
        return "—";
    }

    return escapeHtml(value);
}


function formatDate(value) {
    if (!value) {
        return "Невідомий час";
    }

    const date = new Date(value);

    if (Number.isNaN(date.getTime())) {
        return escapeHtml(value);
    }

    return date.toLocaleString(
        "uk-UA",
        {
            dateStyle: "short",
            timeStyle: "short",
            timeZone: WEATHER_TIME_ZONE,
        }
    );
}


function formatChartTime(
    value,
    includeDate = false
) {
    const date = new Date(value);

    if (Number.isNaN(date.getTime())) {
        return "";
    }

    const parts = new Intl.DateTimeFormat(
        "uk-UA",
        {
            timeZone: WEATHER_TIME_ZONE,
            day: includeDate
                ? "2-digit"
                : undefined,
            month: includeDate
                ? "2-digit"
                : undefined,
            hour: "2-digit",
            minute: "2-digit",
            hourCycle: "h23",
        }
    ).formatToParts(date);

    const partValue = (type) =>
        parts.find(
            (part) => part.type === type
        )?.value || "";

    const time =
        `${partValue("hour")}:` +
        `${partValue("minute")}`;

    if (!includeDate) {
        return time;
    }

    return (
        `${partValue("day")}.` +
        `${partValue("month")} ${time}`
    );
}


function getChartDateKey(value) {
    const date = new Date(value);

    if (Number.isNaN(date.getTime())) {
        return "";
    }

    return new Intl.DateTimeFormat(
        "en-CA",
        {
            timeZone: WEATHER_TIME_ZONE,
            year: "numeric",
            month: "2-digit",
            day: "2-digit",
        }
    ).format(date);
}


// ── Weather card renderer ─────────────────────────────────────────────────

function renderWeather(data) {
    const location = data.location || {};
    const current = data.current || {};
    const units = data.current_units || {};

    weatherResult.classList.remove("empty-state");

    const measurementTime =
        data.requested_at ||
        data.collected_at ||
        current.time;

    weatherResult.innerHTML = `
        <div class="weather-summary">
            <div>
                <span class="weather-overline">
                    Поточні умови
                </span>

                <div class="weather-location">
                    ${valueOrDash(
                        location.name || "Надвірна"
                    )}

                    ${
                        location.country
                            ? `, ${escapeHtml(
                                location.country
                            )}`
                            : ""
                    }
                </div>

                <p class="weather-updated">
                    Дані за ${formatDate(
                        measurementTime
                    )}
                </p>
            </div>

            <div class="temperature">
                ${valueOrDash(
                    current.temperature_2m
                )}

                <span>
                    ${valueOrDash(
                        units.temperature_2m
                    )}
                </span>
            </div>
        </div>

        <div class="weather-details">
            <div class="detail-item">
                <span>Вологість</span>

                <strong>
                    ${valueOrDash(
                        current.relative_humidity_2m
                    )}

                    ${valueOrDash(
                        units.relative_humidity_2m
                    )}
                </strong>
            </div>

            <div class="detail-item">
                <span>Швидкість вітру</span>

                <strong>
                    ${valueOrDash(
                        current.wind_speed_10m
                    )}

                    ${valueOrDash(
                        units.wind_speed_10m
                    )}
                </strong>
            </div>

            <div class="detail-item">
                <span>Час вимірювання</span>

                <strong>
                    ${formatDate(
                        measurementTime
                    )}
                </strong>
            </div>
        </div>
    `;
}


// ── Chart point parsers ───────────────────────────────────────────────────

function getForecastPoints(data) {
    const hourly = data.hourly || {};
    const hourlyUnits =
        data.hourly_units || {};

    const times = Array.isArray(hourly.time)
        ? hourly.time
        : [];

    const temperatures = Array.isArray(
        hourly.temperature_2m
    )
        ? hourly.temperature_2m
        : [];

    const points = times
        .map((rawTime, index) => {
            const timestampSeconds = Number(
                rawTime
            );

            const rawTemperature =
                temperatures[index];

            if (
                rawTemperature === null ||
                rawTemperature === undefined
            ) {
                return null;
            }

            const temperature = Number(
                rawTemperature
            );

            const timestamp =
                timestampSeconds * 1000;

            if (
                !Number.isFinite(timestamp) ||
                !Number.isFinite(temperature)
            ) {
                return null;
            }

            return {
                temperature,
                timestamp,
                time: new Date(
                    timestamp
                ).toISOString(),
            };
        })
        .filter(Boolean)
        .sort(
            (first, second) =>
                first.timestamp - second.timestamp
        );

    return {
        points,
        temperatureUnit:
            hourlyUnits.temperature_2m || "°C",
    };
}


function getHistoryPoints(data) {
    const hourly = data.hourly || {};
    const hourlyUnits = data.hourly_units || {};

    const times = Array.isArray(hourly.time)
        ? hourly.time
        : [];

    const temperatures = Array.isArray(
        hourly.temperature_2m
    )
        ? hourly.temperature_2m
        : [];

    const points = times
        .map((rawTime, index) => {
            const timestampSeconds = Number(rawTime);
            const rawTemperature = temperatures[index];

            if (
                rawTemperature === null ||
                rawTemperature === undefined
            ) {
                return null;
            }

            const temperature = Number(rawTemperature);
            const timestamp = timestampSeconds * 1000;

            if (
                !Number.isFinite(timestamp) ||
                !Number.isFinite(temperature)
            ) {
                return null;
            }

            return {
                temperature,
                timestamp,
                time: new Date(timestamp).toISOString(),
            };
        })
        .filter(Boolean)
        .sort(
            (first, second) =>
                first.timestamp - second.timestamp
        );

    return {
        points,
        temperatureUnit:
            hourlyUnits.temperature_2m || "°C",
    };
}


// ── SVG chart engine ──────────────────────────────────────────────────────

function createSvgElement(name, attributes = {}) {
    const element = document.createElementNS(
        "http://www.w3.org/2000/svg",
        name
    );

    Object.entries(attributes).forEach(
        ([key, value]) => {
            element.setAttribute(key, value);
        }
    );

    return element;
}


function selectChartLabelIndexes(
    points,
    xPosition,
    minimumSpacing
) {
    if (points.length === 0) {
        return [];
    }

    const lastIndex = points.length - 1;

    if (lastIndex === 0) {
        return [0];
    }

    const positionForIndex = (index) =>
        xPosition(points[index], index);

    const firstX = positionForIndex(0);
    const lastX = positionForIndex(lastIndex);

    if (lastX - firstX < minimumSpacing) {
        return [lastIndex];
    }

    const selectedIndexes = [0];

    for (
        let index = 1;
        index < lastIndex;
        index += 1
    ) {
        const previousIndex =
            selectedIndexes[
                selectedIndexes.length - 1
            ];

        if (
            positionForIndex(index) -
            positionForIndex(previousIndex) >=
            minimumSpacing
        ) {
            selectedIndexes.push(index);
        }
    }

    const previousIndex =
        selectedIndexes[
            selectedIndexes.length - 1
        ];

    if (
        lastX - positionForIndex(previousIndex) >=
        minimumSpacing
    ) {
        selectedIndexes.push(lastIndex);

    } else if (previousIndex !== 0) {
        selectedIndexes[
            selectedIndexes.length - 1
        ] = lastIndex;
    }

    return selectedIndexes;
}


/**
 * Render a temperature line chart into the given SVG element.
 *
 * @param {SVGElement} svgElement   - Target SVG element to render into.
 * @param {Array}      points       - [{temperature, timestamp, time}, ...]
 * @param {string}     temperatureUnit
 * @param {HTMLElement} emptyEl     - Element shown when no data.
 * @param {HTMLElement} containerEl - Element wrapping the SVG.
 */
function renderChart(
    svgElement,
    emptyEl,
    containerEl,
    points,
    temperatureUnit = "°C"
) {
    svgElement.replaceChildren();

    if (points.length === 0) {
        containerEl.hidden = true;
        emptyEl.hidden = false;
        emptyEl.textContent =
            "Недостатньо даних для графіка.";
        return;
    }

    emptyEl.hidden = true;
    containerEl.hidden = false;

    const width = 800;
    const height = 360;

    const padding = {
        top: 30,
        right: 45,
        bottom: 65,
        left: 115,
    };

    const chartWidth =
        width - padding.left - padding.right;

    const chartHeight =
        height - padding.top - padding.bottom;

    const temperatures = points.map(
        (point) => point.temperature
    );

    const dateKeys = new Set(
        points.map(
            (point) =>
                getChartDateKey(point.time)
        )
    );

    const spansMultipleDays =
        dateKeys.size > 1;

    let minimum = Math.min(...temperatures);
    let maximum = Math.max(...temperatures);

    if (minimum === maximum) {
        minimum -= 1;
        maximum += 1;
    } else {
        minimum = Math.floor(minimum - 1);
        maximum = Math.ceil(maximum + 1);
    }

    const firstTimestamp =
        points[0].timestamp;

    const lastTimestamp =
        points[points.length - 1].timestamp;

    const timestampRange =
        lastTimestamp - firstTimestamp;

    const xPosition = (point, index) => {
        if (points.length === 1) {
            return padding.left +
                chartWidth / 2;
        }

        if (timestampRange === 0) {
            return padding.left +
                (
                    index /
                    (points.length - 1)
                ) * chartWidth;
        }

        return padding.left +
            (
                (point.timestamp - firstTimestamp) /
                timestampRange
            ) * chartWidth;
    };

    const yPosition = (temperature) => {
        const percentage =
            (temperature - minimum) /
            (maximum - minimum);

        return padding.top +
            chartHeight -
            percentage * chartHeight;
    };

    // Background
    const background = createSvgElement(
        "rect",
        {
            x: padding.left,
            y: padding.top,
            width: chartWidth,
            height: chartHeight,
            class: "chart-background",
        }
    );

    svgElement.appendChild(background);

    // Gradient fill
    const definitions = createSvgElement("defs");

    const gradient = createSvgElement(
        "linearGradient",
        {
            id: `${svgElement.id}-gradient`,
            x1: "0",
            y1: "0",
            x2: "0",
            y2: "1",
        }
    );

    const gradientStart = createSvgElement(
        "stop",
        {
            offset: "0%",
            "stop-color": "#2c756d",
            "stop-opacity": "0.2",
        }
    );

    const gradientEnd = createSvgElement(
        "stop",
        {
            offset: "100%",
            "stop-color": "#2c756d",
            "stop-opacity": "0.01",
        }
    );

    gradient.appendChild(gradientStart);
    gradient.appendChild(gradientEnd);
    definitions.appendChild(gradient);
    svgElement.appendChild(definitions);

    // Area fill
    const area = createSvgElement(
        "polygon",
        {
            points: [
                `${xPosition(points[0], 0)},${
                    height - padding.bottom
                }`,
                ...points.map(
                    (point, index) =>
                        `${xPosition(point, index)},${
                            yPosition(
                                point.temperature
                            )
                        }`
                ),
                `${xPosition(
                    points[points.length - 1],
                    points.length - 1,
                )},${height - padding.bottom}`,
            ].join(" "),
            class: "temperature-area",
            fill: `url(#${svgElement.id}-gradient)`,
        }
    );

    svgElement.appendChild(area);

    // Horizontal grid lines + Y labels
    const horizontalLines = 5;

    for (
        let index = 0;
        index <= horizontalLines;
        index += 1
    ) {
        const percentage =
            index / horizontalLines;

        const y =
            padding.top +
            percentage * chartHeight;

        const temperature =
            maximum -
            percentage * (maximum - minimum);

        const line = createSvgElement(
            "line",
            {
                x1: padding.left,
                y1: y,
                x2: width - padding.right,
                y2: y,
                class: "chart-grid-line",
            }
        );

        const label = createSvgElement(
            "text",
            {
                x: padding.left - 12,
                y: y + 5,
                class: (
                    "chart-label " +
                    "chart-label-y"
                ),
            }
        );

        label.textContent =
            `${temperature.toFixed(1)}` +
            temperatureUnit;

        svgElement.appendChild(line);
        svgElement.appendChild(label);
    }

    // X axis labels
    const renderedWidth =
        containerEl.clientWidth || width;

    const minimumLabelSpacing =
        spansMultipleDays ? 150 : 75;

    const renderedChartWidth =
        chartWidth * renderedWidth / width;

    const maximumLabelCount = Math.max(
        2,
        Math.floor(
            renderedChartWidth /
            minimumLabelSpacing
        ) + 1
    );

    const labelCountLimit = Math.min(
        points.length,
        maximumLabelCount,
        7,
    );

    const minimumChartSpacing = Math.max(
        minimumLabelSpacing *
            width / renderedWidth,
        labelCountLimit > 1
            ? chartWidth /
                (labelCountLimit - 1)
            : chartWidth + 1,
    );

    const labelIndexes =
        selectChartLabelIndexes(
            points,
            xPosition,
            minimumChartSpacing,
        );

    labelIndexes.forEach((index) => {
        const x = xPosition(
            points[index],
            index,
        );

        const line = createSvgElement(
            "line",
            {
                x1: x,
                y1: padding.top,
                x2: x,
                y2: height - padding.bottom,
                class: "chart-grid-line",
            }
        );

        let labelClass =
            "chart-label chart-label-x";

        if (points.length > 1 && index === 0) {
            labelClass +=
                " chart-label-x-start";

        } else if (
            points.length > 1 &&
            index === points.length - 1
        ) {
            labelClass +=
                " chart-label-x-end";
        }

        const label = createSvgElement(
            "text",
            {
                x,
                y: (
                    height -
                    padding.bottom +
                    30
                ),
                class: labelClass,
            }
        );

        label.textContent =
            formatChartTime(
                points[index].time,
                spansMultipleDays
            );

        svgElement.appendChild(line);
        svgElement.appendChild(label);
    });

    // Temperature line
    const polyline = createSvgElement(
        "polyline",
        {
            points: points
                .map(
                    (point, index) =>
                        `${xPosition(point, index)},${
                            yPosition(
                                point.temperature
                            )
                        }`
                )
                .join(" "),
            class: "temperature-line",
        }
    );

    svgElement.appendChild(polyline);

    // Dot markers for labeled points
    const markerIndexes = new Set(labelIndexes);

    points.forEach((point, index) => {
        if (!markerIndexes.has(index)) {
            return;
        }

        const circle = createSvgElement(
            "circle",
            {
                cx: xPosition(point, index),
                cy: yPosition(point.temperature),
                r: 5,
                class: "temperature-point",
            }
        );

        const title = createSvgElement("title");

        title.textContent =
            `${formatDate(point.time)}: ` +
            `${point.temperature}` +
            temperatureUnit;

        circle.appendChild(title);
        svgElement.appendChild(circle);
    });

    // Axis titles
    const xTitle = createSvgElement(
        "text",
        {
            x: width / 2,
            y: height - 10,
            class: "chart-axis-title",
        }
    );

    xTitle.textContent =
        `Час (${WEATHER_TIME_ZONE})`;

    const yTitleX = 28;

    const yTitle = createSvgElement(
        "text",
        {
            x: yTitleX,
            y: height / 2,
            class: "chart-axis-title",
            transform:
                `rotate(-90 ${yTitleX} ${height / 2})`,
        }
    );

    yTitle.textContent =
        `Температура (${temperatureUnit})`;

    svgElement.appendChild(xTitle);
    svgElement.appendChild(yTitle);

    // ── Interactive Hover & Floating Tooltip ───────────────────

    // Create or locate floating tooltip element inside containerEl
    let tooltipEl = containerEl.querySelector(".chart-tooltip");
    if (!tooltipEl) {
        tooltipEl = document.createElement("div");
        tooltipEl.className = "chart-tooltip";
        containerEl.appendChild(tooltipEl);
    }

    // Hover vertical line
    const hoverGuideLine = createSvgElement("line", {
        x1: "0",
        y1: padding.top,
        x2: "0",
        y2: height - padding.bottom,
        class: "chart-hover-line",
    });
    hoverGuideLine.style.display = "none";
    svgElement.appendChild(hoverGuideLine);

    // Hover dot highlight
    const hoverDot = createSvgElement("circle", {
        cx: "0",
        cy: "0",
        r: "6",
        class: "chart-hover-dot",
    });
    hoverDot.style.display = "none";
    svgElement.appendChild(hoverDot);

    function handlePointerMove(evt) {
        const svgRect = svgElement.getBoundingClientRect();
        const containerRect = containerEl.getBoundingClientRect();

        if (svgRect.width === 0 || containerRect.width === 0) {
            return;
        }

        const clientX = evt.touches ? evt.touches[0].clientX : evt.clientX;
        const clientY = evt.touches ? evt.touches[0].clientY : evt.clientY;

        // Check bounds
        if (
            clientX < svgRect.left ||
            clientX > svgRect.right ||
            clientY < svgRect.top ||
            clientY > svgRect.bottom
        ) {
            hideTooltip();
            return;
        }

        const mouseXInSvg = ((clientX - svgRect.left) / svgRect.width) * width;

        // Find closest data point to mouse X
        let closestIndex = 0;
        let minDistance = Infinity;

        points.forEach((point, idx) => {
            const px = xPosition(point, idx);
            const dist = Math.abs(px - mouseXInSvg);
            if (dist < minDistance) {
                minDistance = dist;
                closestIndex = idx;
            }
        });

        const activePoint = points[closestIndex];
        const activeX = xPosition(activePoint, closestIndex);
        const activeY = yPosition(activePoint.temperature);

        // Position vertical hover line & active dot
        hoverGuideLine.setAttribute("x1", activeX);
        hoverGuideLine.setAttribute("x2", activeX);
        hoverGuideLine.style.display = "block";

        hoverDot.setAttribute("cx", activeX);
        hoverDot.setAttribute("cy", activeY);
        hoverDot.style.display = "block";

        // Position floating HTML tooltip relative to container
        const containerX = (activeX / width) * containerRect.width;
        const containerY = (activeY / height) * containerRect.height;

        tooltipEl.innerHTML = `
            <div class="tooltip-time">${formatDate(activePoint.time)}</div>
            <div class="tooltip-temp">${activePoint.temperature.toFixed(1)} ${temperatureUnit}</div>
        `;

        tooltipEl.style.left = `${containerX}px`;
        tooltipEl.style.top = `${containerY}px`;

        // Smart edge alignment
        if (containerX < 70) {
            tooltipEl.style.transform = "translate(0, -100%) translateY(-12px)";
        } else if (containerX > containerRect.width - 70) {
            tooltipEl.style.transform = "translate(-100%, -100%) translateY(-12px)";
        } else {
            tooltipEl.style.transform = "translate(-50%, -100%) translateY(-12px)";
        }

        tooltipEl.classList.add("visible");
    }

    function hideTooltip() {
        hoverGuideLine.style.display = "none";
        hoverDot.style.display = "none";
        tooltipEl.classList.remove("visible");
    }

    svgElement.addEventListener("mousemove", handlePointerMove);
    svgElement.addEventListener("mouseleave", hideTooltip);
    svgElement.addEventListener("touchmove", handlePointerMove, { passive: true });
    svgElement.addEventListener("touchend", hideTooltip);
}


// ── Weather current conditions ────────────────────────────────────────────

async function loadWeather(showLoading = false) {
    if (showLoading) {
        weatherResult.classList.add("empty-state");
        weatherResult.textContent =
            "Завантаження останніх даних...";
    }

    try {
        const response = await fetch(
            "/api/weather",
            { cache: "no-store" }
        );

        const data = await response.json();

        if (!response.ok) {
            weatherResult.classList.add("empty-state");
            weatherResult.textContent =
                data.error ||
                "Не вдалося завантажити погоду.";
            return;
        }

        renderWeather(data);

    } catch {
        weatherResult.classList.add("empty-state");
        weatherResult.textContent =
            "Не вдалося зв'язатися із сервером.";
    }
}


// ── Forecast chart ────────────────────────────────────────────────────────

function showForecastMessage(
    message,
    isError = false,
    statusMessage = message
) {
    forecastChartContainer.hidden = true;
    forecastChartEmpty.hidden = false;
    forecastChartEmpty.textContent = message;
    forecastChartEmpty.classList.toggle(
        "is-error",
        isError
    );

    forecastStatus.textContent = statusMessage;
    forecastStatus.classList.toggle(
        "is-error",
        isError
    );
}


async function loadForecast(showLoading = false) {
    if (forecastAbortController) {
        forecastAbortController.abort();
    }

    const controller = new AbortController();
    forecastAbortController = controller;

    forecastSection.setAttribute(
        "aria-busy",
        "true"
    );

    if (showLoading) {
        showForecastMessage(
            "Завантаження збереженого прогнозу...",
            false,
            "Наступні 24 години · " +
            WEATHER_TIME_ZONE
        );
    }

    try {
        const response = await fetch(
            "/api/forecast",
            {
                cache: "no-store",
                signal: controller.signal,
            }
        );

        const data = await response.json();

        if (!response.ok) {
            const isWaiting =
                response.status === 404;

            showForecastMessage(
                data.error ||
                "Не вдалося завантажити прогноз.",
                !isWaiting,
                isWaiting
                    ? "Прогноз готується у фоні"
                    : (
                        "Прогноз тимчасово " +
                        "недоступний"
                    )
            );

            return;
        }

        const {
            points,
            temperatureUnit,
        } = getForecastPoints(data);

        if (points.length === 0) {
            showForecastMessage(
                "У базі ще немає даних прогнозу.",
                false,
                "Прогноз готується у фоні"
            );

            return;
        }

        forecastChartEmpty.classList.remove(
            "is-error"
        );

        forecastStatus.classList.remove("is-error");

        renderChart(
            forecastTemperatureChart,
            forecastChartEmpty,
            forecastChartContainer,
            points,
            temperatureUnit
        );

        const updateLabel =
            data.last_success_at
                ? ` · оновлено ${
                    formatDate(
                        data.last_success_at
                    )
                }`
                : "";

        const freshnessLabel =
            data.stale
                ? "Попередній прогноз"
                : "Наступні 24 години";

        forecastStatus.textContent =
            `${freshnessLabel} · ` +
            `${points.length} погодинних значень · ` +
            `${temperatureUnit}${updateLabel}`;

        forecastTemperatureChart.setAttribute(
            "aria-label",
            "Погодинний прогноз температури " +
            "у Надвірній на наступні 24 години"
        );

    } catch (error) {
        if (error.name === "AbortError") {
            return;
        }

        showForecastMessage(
            "Не вдалося прочитати прогноз із " +
            "сервера.",
            true,
            "Прогноз тимчасово недоступний"
        );

    } finally {
        if (
            forecastAbortController ===
            controller
        ) {
            forecastAbortController = null;

            forecastSection.setAttribute(
                "aria-busy",
                "false"
            );
        }
    }
}


// ── History chart ─────────────────────────────────────────────────────────

let visibleTableRowsCount = 10;
let lastHistoryData = null;

function renderHistoryTable(data) {
    if (!historyResult) {
        return;
    }

    if (data) {
        lastHistoryData = data;
    } else {
        data = lastHistoryData;
    }

    if (!data) {
        return;
    }

    const hourly = data.hourly || {};
    const units = data.hourly_units || {};
    const times = Array.isArray(hourly.time)
        ? hourly.time
        : [];
    const temperatures =
        Array.isArray(hourly.temperature_2m)
            ? hourly.temperature_2m
            : [];
    const humidities =
        Array.isArray(hourly.relative_humidity_2m)
            ? hourly.relative_humidity_2m
            : [];
    const windSpeeds =
        Array.isArray(hourly.wind_speed_10m)
            ? hourly.wind_speed_10m
            : [];

    const points = times
        .map((rawTime, index) => {
            const timestamp = Number(rawTime) * 1000;
            const temperature = temperatures[index];

            if (
                !Number.isFinite(timestamp) ||
                temperature === null ||
                temperature === undefined
            ) {
                return null;
            }

            return {
                timestamp,
                time: new Date(timestamp).toISOString(),
                temperature: Number(temperature),
                humidity: humidities[index] ?? null,
                wind: windSpeeds[index] ?? null,
            };
        })
        .filter(Boolean)
        .sort((a, b) => b.timestamp - a.timestamp);

    if (points.length === 0) {
        historyResult.classList.add("empty-state");
        historyResult.textContent =
            "У базі даних ще немає вимірювань.";
        return;
    }

    historyResult.classList.remove("empty-state");

    const visiblePoints = points.slice(0, visibleTableRowsCount);
    const hasMore = visibleTableRowsCount < points.length;
    const remainingCount = points.length - visibleTableRowsCount;

    const rows = visiblePoints
        .map((point) => `
            <div class="history-row" role="row">
                <div
                    class="history-cell history-time"
                    role="cell"
                >
                    <strong>Надвірна</strong>
                    <span>${formatDate(point.time)}</span>
                </div>

                <div
                    class="history-cell history-temperature"
                    role="cell"
                >
                    <span class="history-mobile-label">
                        Температура
                    </span>
                    <strong>
                        ${valueOrDash(
                            point.temperature !== null
                                ? point.temperature.toFixed(1)
                                : null
                        )}
                        ${valueOrDash(
                            units.temperature_2m
                        )}
                    </strong>
                </div>

                <div
                    class="history-cell history-humidity"
                    role="cell"
                >
                    <span class="history-mobile-label">
                        Вологість
                    </span>
                    <strong>
                        ${valueOrDash(point.humidity)}
                        ${point.humidity !== null &&
                          point.humidity !== undefined
                            ? valueOrDash(
                                units.relative_humidity_2m
                            )
                            : ""}
                    </strong>
                </div>

                <div
                    class="history-cell history-wind"
                    role="cell"
                >
                    <span class="history-mobile-label">
                        Вітер
                    </span>
                    <strong>
                        ${valueOrDash(point.wind)}
                        ${point.wind !== null &&
                          point.wind !== undefined
                            ? valueOrDash(
                                units.wind_speed_10m
                            )
                            : ""}
                    </strong>
                </div>

                <div
                    class="history-cell history-status"
                    role="cell"
                >
                    <span class="status">Збережено</span>
                </div>
            </div>
        `)
        .join("");

    const loadMoreButtonHtml = hasMore
        ? `
        <div class="table-actions">
            <button
                id="load-more-btn"
                type="button"
                class="load-more-btn"
            >
                Показати ще 10 вимірювань (залишилось ${remainingCount})
            </button>
        </div>
        `
        : "";

    historyResult.innerHTML = `
        <div
            class="history-table"
            role="table"
            aria-label="Історія погодних вимірювань"
        >
            <div class="history-table-header" role="row">
                <span role="columnheader">Місце і час</span>
                <span role="columnheader">Температура</span>
                <span role="columnheader">Вологість</span>
                <span role="columnheader">Вітер</span>
                <span role="columnheader">Статус</span>
            </div>

            <div
                class="history-table-body"
                role="rowgroup"
            >
                ${rows}
            </div>
        </div>
        ${loadMoreButtonHtml}
    `;

    if (hasMore) {
        const loadMoreBtn = document.getElementById("load-more-btn");
        if (loadMoreBtn) {
            loadMoreBtn.addEventListener("click", () => {
                visibleTableRowsCount += 10;
                saveSessionState({ visible_table_rows: visibleTableRowsCount });
                renderHistoryTable();
            });
        }
    }

}


function showHistoryMessage(
    message,
    isError = false,
    statusMessage = message
) {
    historyChartContainer.hidden = true;
    historyChartEmpty.hidden = false;
    historyChartEmpty.textContent = message;
    historyChartEmpty.classList.toggle(
        "is-error",
        isError
    );

    historyStatus.textContent = statusMessage;
    historyStatus.classList.toggle(
        "is-error",
        isError
    );
}


async function loadHistoryChart(
    hours,
    showLoading = false
) {
    if (historyAbortController) {
        historyAbortController.abort();
    }

    const controller = new AbortController();
    historyAbortController = controller;

    historySection.setAttribute(
        "aria-busy",
        "true"
    );

    const rangeLabel =
        hours === 168
            ? "Останні 7 днів"
            : "Останні 24 години";

    if (showLoading) {
        showHistoryMessage(
            "Завантаження даних...",
            false,
            `${rangeLabel} · ${WEATHER_TIME_ZONE}`
        );

        if (historyResult) {
            historyResult.classList.add("empty-state");
            historyResult.textContent =
                "Завантаження історії...";
        }
    }

    try {
        const response = await fetch(
            `/api/history?hours=${hours}`,
            {
                cache: "no-store",
                signal: controller.signal,
            }
        );

        const data = await response.json();

        if (!response.ok) {
            showHistoryMessage(
                data.error ||
                "Не вдалося завантажити історію.",
                true,
                "Помилка завантаження"
            );

            if (historyResult) {
                historyResult.classList.add("empty-state");
                historyResult.textContent =
                    data.error ||
                    "Не вдалося завантажити дані.";
            }

            return;
        }

        const {
            points,
            temperatureUnit,
        } = getHistoryPoints(data);

        // Render chart
        if (points.length === 0) {
            showHistoryMessage(
                "Немає даних за обраний період.",
                false,
                `${rangeLabel} · немає даних`
            );
        } else {
            historyChartEmpty.classList.remove(
                "is-error"
            );

            historyStatus.classList.remove("is-error");

            renderChart(
                historyTemperatureChart,
                historyChartEmpty,
                historyChartContainer,
                points,
                temperatureUnit
            );

            historyStatus.textContent =
                `${rangeLabel} · ` +
                `${points.length} погодинних значень · ` +
                `${temperatureUnit}`;

            historyTemperatureChart.setAttribute(
                "aria-label",
                `Графік температури за ${rangeLabel.toLowerCase()} ` +
                "у Надвірній"
            );
        }

        // Always render the measurements table with fetched history data
        renderHistoryTable(data);

    } catch (error) {
        if (error.name === "AbortError") {
            return;
        }

        showHistoryMessage(
            "Не вдалося прочитати дані із сервера.",
            true,
            "Помилка завантаження"
        );

    } finally {
        if (
            historyAbortController ===
            controller
        ) {
            historyAbortController = null;

            historySection.setAttribute(
                "aria-busy",
                "false"
            );
        }
    }
}


// ── Session preference persistence ────────────────────────────────────────

async function fetchSessionState() {
    try {
        const response = await fetch("/api/session", { cache: "no-store" });
        if (response.ok) {
            const data = await response.json();
            if (data.history_hours && (data.history_hours === 24 || data.history_hours === 168)) {
                currentHistoryHours = data.history_hours;
                const activeBtn = currentHistoryHours === 168 ? historyToggle168 : historyToggle24;
                activateToggle(activeBtn);
            }
            if (data.visible_table_rows && Number.isInteger(data.visible_table_rows)) {
                visibleTableRowsCount = data.visible_table_rows;
            }
        }
    } catch {
        // Silently fall back to default preferences
    }
}

async function saveSessionState(updates) {
    try {
        await fetch("/api/session", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(updates),
        });
    } catch {
        // Ignore session save errors
    }
}


// ── Toggle handlers ───────────────────────────────────────────────────────

function activateToggle(activeButton) {
    [historyToggle24, historyToggle168].forEach(
        (btn) => {
            const isActive = btn === activeButton;
            btn.classList.toggle(
                "toggle-btn-active",
                isActive
            );
            btn.setAttribute(
                "aria-pressed",
                String(isActive)
            );
        }
    );
}


historyToggle24.addEventListener(
    "click",
    async () => {
        if (currentHistoryHours === 24) {
            return;
        }

        currentHistoryHours = 24;
        visibleTableRowsCount = 10;
        activateToggle(historyToggle24);
        loadHistoryChart(24, true);
        await saveSessionState({ history_hours: 24, visible_table_rows: 10 });
    }
);


historyToggle168.addEventListener(
    "click",
    async () => {
        if (currentHistoryHours === 168) {
            return;
        }

        currentHistoryHours = 168;
        visibleTableRowsCount = 10;
        activateToggle(historyToggle168);
        loadHistoryChart(168, true);
        await saveSessionState({ history_hours: 168, visible_table_rows: 10 });
    }
);



// ── Page-level loading ────────────────────────────────────────────────────

async function loadPageData(showLoading = false) {
    if (isLoading) {
        return;
    }

    isLoading = true;

    try {
        await Promise.all([
            loadWeather(showLoading),
            loadForecast(showLoading),
            loadHistoryChart(
                currentHistoryHours,
                showLoading
            ),
        ]);

    } finally {
        isLoading = false;
    }
}


function startAutomaticRefresh() {
    window.setInterval(
        () => {
            loadPageData(false);
        },
        AUTO_REFRESH_INTERVAL_MS
    );
}


// ── Boot ──────────────────────────────────────────────────────────────────

document.addEventListener(
    "DOMContentLoaded",
    async () => {
        await fetchSessionState();
        loadPageData(true);
        startAutomaticRefresh();
    }
);

