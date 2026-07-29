(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) {
    module.exports = api;
  } else {
    root.BlacklistPolling = api;
  }
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  const POLL_INTERVAL_MS = 30000;
  const SVG_NAMESPACE = "http://www.w3.org/2000/svg";

  function svgElement(name, attributes) {
    const element = document.createElementNS(SVG_NAMESPACE, name);
    Object.entries(attributes || {}).forEach(function (entry) {
      element.setAttribute(entry[0], String(entry[1]));
    });
    return element;
  }

  function chartFrame(container) {
    const svg = svgElement("svg", {
      viewBox: "0 0 720 280",
      preserveAspectRatio: "xMidYMid meet",
      "aria-hidden": "true",
      focusable: "false"
    });
    svg.appendChild(svgElement("line", {
      x1: 52, y1: 220, x2: 700, y2: 220, class: "chart-axis"
    }));
    svg.appendChild(svgElement("line", {
      x1: 52, y1: 18, x2: 52, y2: 220, class: "chart-axis"
    }));
    container.replaceChildren(svg);
    return svg;
  }

  function pointX(index, count) {
    return count <= 1 ? 376 : 52 + (index / (count - 1)) * 648;
  }

  function utcDate(value) {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }

  function shortDate(value) {
    return new Intl.DateTimeFormat("en-GB", {
      day: "numeric", month: "short", timeZone: "UTC"
    }).format(value);
  }

  function formatBucketLabel(periodStart, granularity) {
    const start = utcDate(periodStart);
    if (start === null) return "";
    if (granularity === "hour") {
      return new Intl.DateTimeFormat("en-GB", {
        hour: "2-digit", minute: "2-digit", hourCycle: "h23", timeZone: "UTC"
      }).format(start);
    }
    if (granularity === "day") return shortDate(start);
    if (granularity === "month") {
      return new Intl.DateTimeFormat("en-GB", {
        month: "short", year: "numeric", timeZone: "UTC"
      }).format(start);
    }
    const end = new Date(start.getTime() + 6 * 86400000);
    const startMonth = start.getUTCMonth();
    const endMonth = end.getUTCMonth();
    if (startMonth === endMonth) {
      return start.getUTCDate() + "–" + shortDate(end);
    }
    return shortDate(start) + "–" + shortDate(end);
  }

  function visibleLabelIndexes(count, maximum) {
    if (count <= 0) return [];
    const limit = Math.max(2, maximum || 7);
    if (count <= limit) return Array.from({ length: count }, (_, index) => index);
    const indexes = new Set([0, count - 1]);
    const step = (count - 1) / (limit - 1);
    for (let slot = 1; slot < limit - 1; slot += 1) {
      indexes.add(Math.round(slot * step));
    }
    return Array.from(indexes).sort((left, right) => left - right);
  }

  function tooltipText(point, granularity) {
    const label = formatBucketLabel(point.period_start, granularity);
    const value = function (field, suffix) {
      return point[field] == null ? "not available" : point[field] + (suffix || "");
    };
    return [
      label + " UTC (" + point.period_start + ")",
      "Turnover: " + value("turnover_percent", "%"),
      "Added: " + value("added_count"),
      "Removed: " + value("removed_count"),
      "Snapshot: " + value("snapshot_id")
    ].join("\n");
  }

  function appendTitle(element, text) {
    const title = svgElement("title");
    title.textContent = text;
    element.appendChild(title);
  }

  function appendXAxisLabels(svg, points, granularity) {
    visibleLabelIndexes(points.length, 7).forEach(function (index) {
      const x = pointX(index, points.length);
      svg.appendChild(svgElement("line", {
        x1: x, y1: 220, x2: x, y2: 225, class: "chart-tick"
      }));
      const label = svgElement("text", {
        x: x,
        y: 239,
        class: "chart-tick-label",
        "text-anchor": index === 0 ? "start" : (index === points.length - 1 ? "end" : "middle")
      });
      label.textContent = formatBucketLabel(points[index].period_start, granularity);
      svg.appendChild(label);
    });
    const xLabel = svgElement("text", {
      x: 376, y: 270, class: "chart-axis-label"
    });
    xLabel.textContent = granularity[0].toUpperCase() + granularity.slice(1) + " UTC buckets";
    svg.appendChild(xLabel);
  }

  function appendHitTargets(svg, points, granularity) {
    const spacing = points.length <= 1 ? 648 : 648 / (points.length - 1);
    points.forEach(function (point, index) {
      const center = pointX(index, points.length);
      const left = Math.max(52, center - spacing / 2);
      const right = Math.min(700, center + spacing / 2);
      const target = svgElement("rect", {
        x: left,
        y: 18,
        width: right - left,
        height: 202,
        class: "chart-hit-target",
        tabindex: "0"
      });
      appendTitle(target, tooltipText(point, granularity));
      svg.appendChild(target);
    });
  }

  function renderLineChart(container, points, granularity) {
    const svg = chartFrame(container);
    let segment = [];

    function appendSegment() {
      if (segment.length > 1) {
        svg.appendChild(svgElement("polyline", {
          points: segment.join(" "),
          class: "turnover-line",
          fill: "none"
        }));
      } else if (segment.length === 1) {
        const coordinates = segment[0].split(",");
        svg.appendChild(svgElement("circle", {
          cx: coordinates[0], cy: coordinates[1], r: 3, class: "turnover-point"
        }));
      }
      segment = [];
    }

    points.forEach(function (point, index) {
      if (point.turnover_percent == null) {
        appendSegment();
        return;
      }
      const value = Math.max(0, Math.min(100, Number(point.turnover_percent)));
      segment.push(pointX(index, points.length) + "," + (220 - value * 2));
    });
    appendSegment();

    const yLabel = svgElement("text", {
      x: 14, y: 125, class: "chart-axis-label",
      transform: "rotate(-90 14 125)"
    });
    yLabel.textContent = "Turnover percent";
    svg.appendChild(yLabel);
    appendXAxisLabels(svg, points, granularity);
    appendHitTargets(svg, points, granularity);
  }

  function renderBarChart(container, points, granularity) {
    const svg = chartFrame(container);
    const values = points.flatMap(function (point) {
      return [point.added_count, point.removed_count]
        .filter(function (value) { return value != null; })
        .map(Number);
    });
    const maximum = Math.max(1, ...values);
    const groupWidth = 648 / Math.max(points.length, 1);
    const barWidth = Math.max(2, Math.min(14, groupWidth * 0.3));

    points.forEach(function (point, index) {
      const center = 52 + groupWidth * (index + 0.5);
      [
        ["added_count", "bar-added", center - barWidth],
        ["removed_count", "bar-removed", center]
      ].forEach(function (definition) {
        const value = point[definition[0]];
        if (value == null) return;
        const height = Math.max(0, Number(value)) / maximum * 190;
        const bar = svgElement("rect", {
          x: definition[2],
          y: 220 - height,
          width: barWidth,
          height: height,
          class: definition[1]
        });
        appendTitle(bar, tooltipText(point, granularity));
        svg.appendChild(bar);
      });
    });

    const yLabel = svgElement("text", {
      x: 14, y: 125, class: "chart-axis-label",
      transform: "rotate(-90 14 125)"
    });
    yLabel.textContent = "IP address count";
    svg.appendChild(yLabel);
    appendXAxisLabels(svg, points, granularity);
    appendHitTargets(svg, points, granularity);
  }

  function renderTurnoverCharts(rootElement) {
    const scope = rootElement || document;
    scope.querySelectorAll("[data-turnover-chart]").forEach(function (container) {
      let points;
      try {
        points = JSON.parse(container.dataset.points || "[]");
      } catch (_error) {
        return;
      }
      const granularity = container.dataset.granularity || "day";
      if (container.dataset.turnoverChart === "line") {
        renderLineChart(container, points, granularity);
      } else {
        renderBarChart(container, points, granularity);
      }
    });
  }

  function snapshotChanged(currentSnapshotId, latestSnapshotId) {
    return currentSnapshotId !== latestSnapshotId;
  }

  function indicatorMessage(state) {
    if (state === "stale") return "The displayed blacklist snapshot is stale.";
    if (state === "degraded") {
      return "The latest synchronization failed. The most recent valid snapshot remains available.";
    }
    if (state === "syncing") {
      return "A synchronization is in progress. The latest successful snapshot remains available below.";
    }
    if (state === "empty") return "No successful blacklist snapshot is available yet.";
    return "The latest blacklist snapshot is ready.";
  }

  function createPoller(options) {
    let timer = null;
    let inFlight = false;
    let stopped = false;

    function schedule() {
      if (!stopped && !options.isHidden()) {
        timer = options.setTimer(poll, options.interval || POLL_INTERVAL_MS);
      }
    }

    async function poll() {
      if (stopped || inFlight || options.isHidden()) return;
      inFlight = true;
      try {
        const status = await options.fetchStatus();
        if (snapshotChanged(options.currentSnapshotId, status.latest_snapshot_id)) {
          options.reload();
          return;
        }
        options.updateIndicator(status.state, status.data_stale);
      } catch (_error) {
        // Keep the currently rendered snapshot and status after polling failures.
      } finally {
        inFlight = false;
        schedule();
      }
    }

    function visibilityChanged() {
      if (options.isHidden()) {
        if (timer !== null) options.clearTimer(timer);
        timer = null;
      } else if (!inFlight) {
        void poll();
      }
    }

    function start() {
      schedule();
    }

    function stop() {
      stopped = true;
      if (timer !== null) options.clearTimer(timer);
      timer = null;
    }

    return { poll, start, stop, visibilityChanged };
  }

  function start(options) {
    renderTurnoverCharts(document);
    const poller = createPoller({
      currentSnapshotId: options.currentSnapshotId,
      interval: POLL_INTERVAL_MS,
      isHidden: function () { return document.hidden; },
      setTimer: window.setTimeout.bind(window),
      clearTimer: window.clearTimeout.bind(window),
      fetchStatus: async function () {
        const response = await fetch(options.statusUrl, {
          headers: { Accept: "application/json" },
          cache: "no-store"
        });
        if (!response.ok) throw new Error("Status request failed");
        return response.json();
      },
      reload: function () { window.location.reload(); },
      updateIndicator: function (state, dataStale) {
        options.indicator.dataset.state = state;
        options.indicator.className = (state === "stale" || state === "degraded" || dataStale) ? "warning" : "";
        options.indicator.textContent = indicatorMessage(state);
      }
    });
    document.addEventListener("visibilitychange", poller.visibilityChanged);
    poller.start();
    return poller;
  }

  return {
    createPoller,
    formatBucketLabel,
    indicatorMessage,
    renderTurnoverCharts,
    snapshotChanged,
    start,
    tooltipText,
    visibleLabelIndexes
  };
});
