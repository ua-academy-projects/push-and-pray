const searchForm = document.querySelector("#search-form");
const cityInput = document.querySelector("#city-input");
const searchButton = document.querySelector("#search-button");
const refreshButton = document.querySelector("#refresh-button");

const statusMessage = document.querySelector("#status-message");

const currentSection = document.querySelector("#current-section");
const currentHeading = document.querySelector("#current-heading");
const locationDetails = document.querySelector("#location-details");
const aqiSummary = document.querySelector("#aqi-summary");
const metricsGrid = document.querySelector("#metrics-grid");
const historySaveState = document.querySelector("#history-save-state");

const historyMessage = document.querySelector("#history-message");
const historyTableBody = document.querySelector("#history-table-body");
const reloadHistoryButton = document.querySelector(
    "#reload-history-button"
);

const previousPageButton = document.querySelector(
    "#previous-page-button"
);
const nextPageButton = document.querySelector(
    "#next-page-button"
);
const pageInformation = document.querySelector("#page-information");

const historyDialog = document.querySelector("#history-dialog");
const historyDialogContent = document.querySelector(
    "#history-dialog-content"
);
const closeDialogButton = document.querySelector(
    "#close-dialog-button"
);

const historyPageSize = 10;

let lastSearchedCity = "";
let historyOffset = 0;
let historyTotal = 0;


searchForm.addEventListener("submit", async (event) => {
    event.preventDefault();

    const city = cityInput.value.trim();

    if (city.length < 2) {
        showStatus(
            statusMessage,
            "Enter at least two non-space characters.",
            "error"
        );
        return;
    }

    lastSearchedCity = city;
    await loadAirQuality(city);
});


refreshButton.addEventListener("click", async () => {
    if (!lastSearchedCity) {
        return;
    }

    await loadAirQuality(lastSearchedCity);
});


reloadHistoryButton.addEventListener("click", async () => {
    historyOffset = 0;
    await loadHistory();
});


previousPageButton.addEventListener("click", async () => {
    historyOffset = Math.max(
        0,
        historyOffset - historyPageSize
    );

    await loadHistory();
});


nextPageButton.addEventListener("click", async () => {
    if (historyOffset + historyPageSize >= historyTotal) {
        return;
    }

    historyOffset += historyPageSize;
    await loadHistory();
});


closeDialogButton.addEventListener("click", () => {
    historyDialog.close();
});


historyDialog.addEventListener("click", (event) => {
    if (event.target === historyDialog) {
        historyDialog.close();
    }
});


async function loadAirQuality(city) {
    setSearchLoading(true);

    showStatus(
        statusMessage,
        `Loading air-quality data for ${city}...`
    );

    try {
        const response = await fetch(
            `/api/air-quality?city=${encodeURIComponent(city)}`
        );

        const payload = await readJsonResponse(response);

        if (!response.ok) {
            throw new Error(
                extractErrorMessage(payload)
            );
        }

        renderAirQuality(payload);

        showStatus(
            statusMessage,
            "Current air-quality data loaded.",
            "success"
        );

        await loadHistory();

    } catch (error) {
        showStatus(
            statusMessage,
            error.message || "Could not load air-quality data.",
            "error"
        );
    } finally {
        setSearchLoading(false);
    }
}


function renderAirQuality(payload) {
    const location = payload.location;
    const airQuality = payload.air_quality;

    currentHeading.textContent =
        `Air quality in ${location.name}`;

    const locationParts = [
        location.admin1,
        location.country,
        location.timezone,
    ].filter(Boolean);

    locationDetails.textContent = locationParts.join(" · ");

    const primaryAqi =
        airQuality.european_aqi ?? airQuality.us_aqi;

    const aqiType =
        airQuality.european_aqi !== null
        && airQuality.european_aqi !== undefined
            ? "European AQI"
            : "US AQI";

    const classification = classifyEuropeanAqi(
        airQuality.european_aqi
    );

    aqiSummary.innerHTML = "";

    const summaryLabel = document.createElement("span");
    summaryLabel.className = "metric-label";
    summaryLabel.textContent = aqiType;

    const summaryValue = document.createElement("strong");
    summaryValue.textContent = formatValue(primaryAqi);

    const summaryDescription = document.createElement("div");
    summaryDescription.className = "aqi-description";
    summaryDescription.textContent =
        `${classification} · Observed at `
        + `${formatDateTime(airQuality.observed_at)}`;

    aqiSummary.append(
        summaryLabel,
        summaryValue,
        summaryDescription
    );

    const metrics = [
        {
            label: "European AQI",
            value: airQuality.european_aqi,
            unit: "",
        },
        {
            label: "US AQI",
            value: airQuality.us_aqi,
            unit: "",
        },
        {
            label: "PM2.5",
            value: airQuality.pm2_5,
            unit: "μg/m³",
        },
        {
            label: "PM10",
            value: airQuality.pm10,
            unit: "μg/m³",
        },
        {
            label: "Nitrogen dioxide",
            value: airQuality.nitrogen_dioxide,
            unit: "μg/m³",
        },
        {
            label: "Ozone",
            value: airQuality.ozone,
            unit: "μg/m³",
        },
        {
            label: "Carbon monoxide",
            value: airQuality.carbon_monoxide,
            unit: "μg/m³",
        },
        {
            label: "UV index",
            value: airQuality.uv_index,
            unit: "",
        },
    ];

    metricsGrid.replaceChildren(
        ...metrics.map(createMetricCard)
    );

    historySaveState.textContent = payload.history_saved
        ? "Saved to history"
        : "History not saved";

    historySaveState.className = payload.history_saved
        ? "status-badge saved"
        : "status-badge not-saved";

    currentSection.classList.remove("hidden");
    refreshButton.disabled = false;
}


function createMetricCard(metric) {
    const card = document.createElement("article");
    card.className = "metric-card";

    const label = document.createElement("div");
    label.className = "metric-label";
    label.textContent = metric.label;

    const valueWrapper = document.createElement("div");
    valueWrapper.className = "metric-value";

    const value = document.createElement("span");
    value.textContent = formatValue(metric.value);

    valueWrapper.appendChild(value);

    if (metric.unit) {
        const unit = document.createElement("span");
        unit.className = "metric-unit";
        unit.textContent = metric.unit;

        valueWrapper.appendChild(unit);
    }

    card.append(label, valueWrapper);

    return card;
}


async function loadHistory() {
    showStatus(historyMessage, "Loading history...");

    try {
        const response = await fetch(
            `/api/history?limit=${historyPageSize}`
            + `&offset=${historyOffset}`
        );

        const payload = await readJsonResponse(response);

        if (!response.ok) {
            throw new Error(
                extractErrorMessage(payload)
            );
        }

        historyTotal = payload.total;
        renderHistoryRows(payload.items);
        updatePagination();

        if (payload.items.length === 0) {
            showStatus(
                historyMessage,
                "No history records found."
            );
        } else {
            showStatus(historyMessage, "");
        }

    } catch (error) {
        historyTableBody.replaceChildren();

        showStatus(
            historyMessage,
            error.message || "Could not load history.",
            "error"
        );
    }
}


function renderHistoryRows(items) {
    historyTableBody.replaceChildren(
        ...items.map(createHistoryRow)
    );
}


function createHistoryRow(record) {
    const row = document.createElement("tr");

    const requestedAtCell = document.createElement("td");
    requestedAtCell.textContent =
        formatDateTime(record.created_at);

    const cityCell = document.createElement("td");
    cityCell.textContent =
        record.query_parameters?.city ?? "Unknown";

    const sourceCell = document.createElement("td");
    sourceCell.textContent = record.source;

    const statusCell = document.createElement("td");
    statusCell.textContent = record.source_status_code;

    const detailsCell = document.createElement("td");
    const detailsButton = document.createElement("button");

    detailsButton.type = "button";
    detailsButton.className = "table-action";
    detailsButton.textContent = "View";

    detailsButton.addEventListener("click", async () => {
        await showHistoryRecord(record.id);
    });

    detailsCell.appendChild(detailsButton);

    row.append(
        requestedAtCell,
        cityCell,
        sourceCell,
        statusCell,
        detailsCell
    );

    return row;
}


async function showHistoryRecord(recordId) {
    historyDialogContent.textContent = "Loading...";
    historyDialog.showModal();

    try {
        const response = await fetch(
            `/api/history/${recordId}`
        );

        const payload = await readJsonResponse(response);

        if (!response.ok) {
            throw new Error(
                extractErrorMessage(payload)
            );
        }

        renderHistoryDialog(payload);

    } catch (error) {
        historyDialogContent.textContent =
            error.message || "Could not load history record.";
    }
}


function renderHistoryDialog(record) {
    const summaryBlock = createDetailBlock(
        "Summary",
        {
            id: record.id,
            created_at: record.created_at,
            request_type: record.request_type,
            result_count: record.result_count,
            source: record.source,
            source_status_code: record.source_status_code,
        }
    );

    const queryBlock = createDetailBlock(
        "Query parameters",
        record.query_parameters
    );

    const responseBlock = createDetailBlock(
        "Saved response",
        record.response_data
    );

    historyDialogContent.replaceChildren(
        summaryBlock,
        queryBlock,
        responseBlock
    );
}


function createDetailBlock(title, data) {
    const block = document.createElement("section");
    block.className = "detail-block";

    const heading = document.createElement("h3");
    heading.textContent = title;

    const content = document.createElement("pre");
    content.textContent = JSON.stringify(data, null, 2);

    block.append(heading, content);

    return block;
}


function updatePagination() {
    const currentPage =
        Math.floor(historyOffset / historyPageSize) + 1;

    const pageCount = Math.max(
        1,
        Math.ceil(historyTotal / historyPageSize)
    );

    pageInformation.textContent =
        `Page ${currentPage} of ${pageCount}`;

    previousPageButton.disabled = historyOffset === 0;

    nextPageButton.disabled =
        historyOffset + historyPageSize >= historyTotal;
}


function setSearchLoading(isLoading) {
    searchButton.disabled = isLoading;
    cityInput.disabled = isLoading;

    searchButton.textContent = isLoading
        ? "Loading..."
        : "Check air quality";

    refreshButton.disabled =
        isLoading || !lastSearchedCity;
}


function showStatus(element, message, type = "") {
    element.textContent = message;
    element.className = "status-message";

    if (type) {
        element.classList.add(type);
    }
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


function formatDateTime(value) {
    if (!value) {
        return "Unknown";
    }

    const date = new Date(value);

    if (Number.isNaN(date.getTime())) {
        return value;
    }

    return new Intl.DateTimeFormat(
        undefined,
        {
            dateStyle: "medium",
            timeStyle: "short",
        }
    ).format(date);
}


function classifyEuropeanAqi(value) {
    if (value === null || value === undefined) {
        return "No AQI classification available";
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


loadHistory();