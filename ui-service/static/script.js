const AUTO_REFRESH_INTERVAL_MS = 60_000;
const WEATHER_TIME_ZONE = "Europe/Kyiv";

const clearHistoryButton =
    document.getElementById(
        "clear-history-button"
    );

const weatherResult =
    document.getElementById("weather-result");

const historyResult =
    document.getElementById("history-result");

const chartEmpty =
    document.getElementById("chart-empty");

const chartContainer =
    document.getElementById("chart-container");

const temperatureChart =
    document.getElementById(
        "temperature-chart"
    );

let isLoading = false;


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


function renderWeather(data) {
    const location = data.location || {};
    const current = data.current || {};
    const units = data.current_units || {};

    weatherResult.classList.remove(
        "empty-state"
    );

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


function getHistoryPoints(data) {
    const items = Array.isArray(data.items)
        ? data.items
        : [];

    return items
        .map((item) => {
            const responseData =
                item.response_data || {};

            const current =
                responseData.current || {};

            const temperature = Number(
                current.temperature_2m
            );

            const time =
                item.requested_at ||
                responseData.collected_at ||
                current.time;

            const timestamp = new Date(
                time
            ).getTime();

            if (
                !Number.isFinite(temperature) ||
                !time ||
                !Number.isFinite(timestamp)
            ) {
                return null;
            }

            return {
                id: item.id,
                temperature,
                time,
                timestamp,
                humidity:
                    current.relative_humidity_2m,
                wind:
                    current.wind_speed_10m,
                units:
                    responseData.current_units || {},
            };
        })
        .filter(Boolean)
        .sort(
            (first, second) =>
                first.timestamp - second.timestamp
        );
}


function renderHistory(points) {
    if (points.length === 0) {
        historyResult.classList.add(
            "empty-state"
        );

        historyResult.textContent =
            "У базі даних ще немає вимірювань.";

        return;
    }

    historyResult.classList.remove(
        "empty-state"
    );

    const rows = [...points]
        .reverse()
        .map((point) => `
            <div
                class="history-row"
                role="row"
            >
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
                            point.temperature
                        )}

                        ${valueOrDash(
                            point.units.temperature_2m
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
                        ${valueOrDash(
                            point.humidity
                        )}

                        ${valueOrDash(
                            point.units
                                .relative_humidity_2m
                        )}
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
                        ${valueOrDash(
                            point.wind
                        )}

                        ${valueOrDash(
                            point.units.wind_speed_10m
                        )}
                    </strong>
                </div>

                <div
                    class="history-cell history-status"
                    role="cell"
                >
                    <span class="status">
                        Збережено
                    </span>
                </div>
            </div>
        `)
        .join("");

    historyResult.innerHTML = `
        <div
            class="history-table"
            role="table"
            aria-label="Історія погодних вимірювань"
        >
            <div
                class="history-table-header"
                role="row"
            >
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
    `;
}


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


function renderChart(points) {
    temperatureChart.replaceChildren();

    if (points.length === 0) {
        chartContainer.hidden = true;
        chartEmpty.hidden = false;

        chartEmpty.textContent =
            "Недостатньо даних для графіка.";

        return;
    }

    chartEmpty.hidden = true;
    chartContainer.hidden = false;

    const width = 800;
    const height = 360;

    const padding = {
        top: 30,
        right: 30,
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

    temperatureChart.appendChild(background);

    const definitions = createSvgElement(
        "defs"
    );

    const gradient = createSvgElement(
        "linearGradient",
        {
            id: "temperature-area-gradient",
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
    temperatureChart.appendChild(definitions);

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
        }
    );

    temperatureChart.appendChild(area);

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
            `${temperature.toFixed(1)}°C`;

        temperatureChart.appendChild(line);
        temperatureChart.appendChild(label);
    }

    const renderedWidth =
        chartContainer.clientWidth || width;

    const minimumLabelSpacing =
        spansMultipleDays ? 115 : 75;

    const maximumLabelCount = Math.max(
        2,
        Math.floor(
            renderedWidth /
            minimumLabelSpacing
        )
    );

    const labelCount = Math.min(
        points.length,
        maximumLabelCount,
        7,
    );

    const labelIndexes = new Set();

    if (labelCount === 1) {
        labelIndexes.add(0);

    } else {
        for (
            let index = 0;
            index < labelCount;
            index += 1
        ) {
            labelIndexes.add(
                Math.round(
                    index *
                    (points.length - 1) /
                    (labelCount - 1)
                )
            );
        }
    }

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

        const label = createSvgElement(
            "text",
            {
                x,
                y: (
                    height -
                    padding.bottom +
                    30
                ),
                class: (
                    "chart-label " +
                    "chart-label-x"
                ),
            }
        );

        label.textContent =
            formatChartTime(
                points[index].time,
                spansMultipleDays
            );

        temperatureChart.appendChild(line);
        temperatureChart.appendChild(label);
    });

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

    temperatureChart.appendChild(polyline);

    points.forEach((point, index) => {
        const circle = createSvgElement(
            "circle",
            {
                cx: xPosition(point, index),
                cy: yPosition(
                    point.temperature
                ),
                r: 5,
                class: "temperature-point",
            }
        );

        const title = createSvgElement(
            "title"
        );

        title.textContent =
            `${formatDate(point.time)}: ` +
            `${point.temperature}°C`;

        circle.appendChild(title);
        temperatureChart.appendChild(circle);
    });

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

    yTitle.textContent = "Температура";

    temperatureChart.appendChild(xTitle);
    temperatureChart.appendChild(yTitle);
}


async function loadWeather(
    showLoading = false
) {
    if (showLoading) {
        weatherResult.classList.add(
            "empty-state"
        );

        weatherResult.textContent =
            "Завантаження останніх даних...";
    }

    try {
        const response = await fetch(
            "/api/weather",
            {
                cache: "no-store",
            }
        );

        const data = await response.json();

        if (!response.ok) {
            weatherResult.classList.add(
                "empty-state"
            );

            weatherResult.textContent =
                data.error ||
                "Не вдалося завантажити погоду.";

            return;
        }

        renderWeather(data);

    } catch (error) {
        weatherResult.classList.add(
            "empty-state"
        );

        weatherResult.textContent =
            "Не вдалося зв’язатися із сервером.";
    }
}


async function loadHistory(
    showLoading = false
) {
    if (showLoading) {
        historyResult.classList.add(
            "empty-state"
        );

        historyResult.textContent =
            "Завантаження історії...";

        chartContainer.hidden = true;
        chartEmpty.hidden = false;

        chartEmpty.textContent =
            "Завантаження графіка...";
    }

    try {
        const response = await fetch(
            "/api/history",
            {
                cache: "no-store",
            }
        );

        const data = await response.json();

        if (!response.ok) {
            const errorMessage =
                data.error ||
                "Не вдалося завантажити історію.";

            historyResult.classList.add(
                "empty-state"
            );

            historyResult.textContent =
                errorMessage;

            chartContainer.hidden = true;
            chartEmpty.hidden = false;
            chartEmpty.textContent =
                errorMessage;

            return;
        }

        const points =
            getHistoryPoints(data);

        renderHistory(points);
        renderChart(points);

    } catch (error) {
        historyResult.classList.add(
            "empty-state"
        );

        historyResult.textContent =
            "Не вдалося зв’язатися із сервером.";

        chartContainer.hidden = true;
        chartEmpty.hidden = false;

        chartEmpty.textContent =
            "Не вдалося завантажити графік.";
    }
}


async function loadPageData(
    showLoading = false
) {
    if (isLoading) {
        return;
    }

    isLoading = true;

    try {
        await Promise.all([
            loadWeather(showLoading),
            loadHistory(showLoading),
        ]);

    } finally {
        isLoading = false;
    }
}


async function clearHistory() {
    const confirmed = window.confirm(
        "Очистити історію та одразу " +
        "отримати нові погодні дані?"
    );

    if (!confirmed) {
        return;
    }

    clearHistoryButton.disabled = true;
    clearHistoryButton.textContent =
        "Очищення...";

    weatherResult.classList.add(
        "empty-state"
    );

    weatherResult.textContent =
        "Отримання нових погодних даних...";

    try {
        const response = await fetch(
            "/api/history",
            {
                method: "DELETE",
                cache: "no-store",
            }
        );

        const data = await response.json();

        if (!response.ok) {
            weatherResult.textContent =
                data.error ||
                "Не вдалося очистити історію.";

            return;
        }

        await loadPageData(true);

    } catch (error) {
        weatherResult.textContent =
            "Не вдалося зв’язатися із сервером.";

    } finally {
        clearHistoryButton.disabled = false;

        clearHistoryButton.textContent =
            "Очистити історію";
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


clearHistoryButton.addEventListener(
    "click",
    clearHistory
);

document.addEventListener(
    "DOMContentLoaded",
    () => {
        loadPageData(true);
        startAutomaticRefresh();
    }
);
