import { LineChart, type LineSeriesOption } from "echarts/charts";
import {
  DataZoomComponent,
  GridComponent,
  LegendComponent,
  ToolboxComponent,
  TooltipComponent,
  type DataZoomComponentOption,
  type GridComponentOption,
  type LegendComponentOption,
  type ToolboxComponentOption,
  type TooltipComponentOption,
} from "echarts/components";
import * as echarts from "echarts/core";
import type { ComposeOption } from "echarts/core";
import { CanvasRenderer } from "echarts/renderers";
import { useEffect, useMemo, useRef } from "react";

import { formatDateTime, formatPercent, formatPrice } from "./format";
import { rollingAverage } from "./data";
import type { ChartGroup, ChartStyle, Metric, MovingAverage, Scale } from "./types";

interface ChartPanelProps {
  group: ChartGroup;
  metric: Metric;
  style: ChartStyle;
  scale: Scale;
  smooth: boolean;
  movingAverage: MovingAverage;
}

interface TooltipPoint {
  marker?: string;
  seriesName?: string;
  data?: [number, number, number, string, string];
}

type ChartOption = ComposeOption<
  | LineSeriesOption
  | DataZoomComponentOption
  | GridComponentOption
  | LegendComponentOption
  | ToolboxComponentOption
  | TooltipComponentOption
>;

echarts.use([
  LineChart,
  DataZoomComponent,
  GridComponent,
  LegendComponent,
  ToolboxComponent,
  TooltipComponent,
  CanvasRenderer,
]);

const escapeHtml = (value: unknown): string =>
  String(value ?? "").replace(
    /[&<>'"]/g,
    (character) =>
      ({
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        "'": "&#39;",
        '"': "&quot;",
      })[character] ?? character,
  );

export default function ChartPanel({
  group,
  metric,
  style,
  scale,
  smooth,
  movingAverage,
}: ChartPanelProps) {
  const chartElement = useRef<HTMLDivElement>(null);

  const option = useMemo<ChartOption>(() => {
    const mainSeries = group.series.map((series) => ({
      id: series.code,
      name: series.name,
      type: "line" as const,
      data: series.points.map((point) => [
        point.time,
        point.value,
        point.raw,
        point.observation.source,
        point.observation.source_observed_at,
      ]),
      smooth: smooth ? 0.24 : false,
      showSymbol: style === "points",
      symbol: "circle",
      symbolSize: style === "points" ? 8 : 5,
      sampling: "lttb" as const,
      connectNulls: true,
      lineStyle: {
        width: style === "points" ? 0 : 2.5,
        color: series.color,
      },
      itemStyle: {
        color: series.color,
        borderColor: "#101815",
        borderWidth: 2,
      },
      areaStyle:
        style === "area"
          ? {
              color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
                { offset: 0, color: `${series.color}4d` },
                { offset: 1, color: `${series.color}05` },
              ]),
            }
          : undefined,
      emphasis: {
        focus: "series" as const,
        lineStyle: { width: 3.5 },
      },
    }));

    const averageWindow = movingAverage === "off" ? 0 : Number(movingAverage);
    const averageSeries =
      averageWindow > 0
        ? group.series.map((series) => ({
            id: `${series.code}-average`,
            name: `${series.name} · MA${averageWindow}`,
            type: "line" as const,
            data: rollingAverage(series.points, averageWindow).map((point) => [
              point.time,
              point.value,
              point.raw,
              point.observation.source,
              point.observation.source_observed_at,
            ]),
            showSymbol: false,
            smooth: 0.3,
            silent: true,
            lineStyle: {
              width: 1.5,
              type: "dashed" as const,
              opacity: 0.72,
              color: series.color,
            },
          }))
        : [];

    return {
      animationDuration: 550,
      animationEasing: "cubicOut",
      backgroundColor: "transparent",
      color: group.series.map((series) => series.color),
      grid: {
        top: 72,
        left: 72,
        right: 34,
        bottom: 82,
        containLabel: false,
      },
      legend: {
        top: 18,
        left: 18,
        icon: "roundRect",
        itemWidth: 18,
        itemHeight: 3,
        itemGap: 24,
        textStyle: {
          color: "#b5c0ba",
          fontSize: 11,
          fontWeight: 600,
        },
        data: group.series.map((series) => series.name),
      },
      tooltip: {
        trigger: "axis",
        confine: true,
        backgroundColor: "rgba(9, 14, 12, .96)",
        borderColor: "#33413b",
        borderWidth: 1,
        padding: 14,
        textStyle: { color: "#edf2ee" },
        axisPointer: {
          type: "cross",
          snap: true,
          lineStyle: { color: "#6e8077", type: "dashed" },
          crossStyle: { color: "#6e8077", type: "dashed" },
          label: {
            color: "#edf2ee",
            backgroundColor: "#26322d",
          },
        },
        formatter: (rawParameters: unknown) => {
          const parameters = (Array.isArray(rawParameters)
            ? rawParameters
            : [rawParameters]) as TooltipPoint[];
          const first = parameters.find((item) => item.data)?.data;
          if (!first) return "";
          const rows = parameters
            .filter((item) => item.data && !item.seriesName?.includes("· MA"))
            .map((item) => {
              const data = item.data!;
              const shown =
                metric === "change"
                  ? formatPercent(Number(data[1]))
                  : `${formatPrice(Number(data[1]))} USD`;
              return `<div class="chart-tip-row">
                <span>${item.marker ?? ""}${escapeHtml(item.seriesName)}</span>
                <strong>${escapeHtml(shown)}</strong>
              </div>`;
            })
            .join("");
          return `<div class="chart-tip">
            <time>${escapeHtml(formatDateTime(first[4] || first[0]))} UTC</time>
            ${rows}
            <small>Source: ${escapeHtml(first[3])}</small>
          </div>`;
        },
      },
      toolbox: {
        top: 14,
        right: 18,
        itemSize: 15,
        iconStyle: {
          borderColor: "#829189",
        },
        emphasis: {
          iconStyle: { borderColor: "#de8051" },
        },
        feature: {
          dataZoom: { yAxisIndex: "none", title: { zoom: "Zoom", back: "Back" } },
          restore: { title: "Reset" },
          saveAsImage: {
            title: "Export PNG",
            name: `petroscope-${group.key}`,
            backgroundColor: "#101815",
            pixelRatio: 2,
          },
        },
      },
      xAxis: {
        type: "time",
        boundaryGap: [0, 0],
        axisLine: { lineStyle: { color: "#34413b" } },
        axisTick: { show: false },
        axisLabel: {
          color: "#7f8d86",
          hideOverlap: true,
          fontSize: 10,
          margin: 14,
        },
        splitLine: {
          show: true,
          lineStyle: { color: "rgba(147, 166, 157, .08)", type: "dashed" },
        },
      },
      yAxis: {
        type: metric === "price" && scale === "log" ? "log" : "value",
        scale: true,
        name: metric === "change" ? "CHANGE, %" : "USD",
        nameTextStyle: {
          color: "#718078",
          align: "right",
          padding: [0, 0, 8, 0],
          fontSize: 10,
        },
        axisLine: { show: false },
        axisTick: { show: false },
        axisLabel: {
          color: "#8a9891",
          fontSize: 10,
          formatter: (value: number) =>
            metric === "change" ? `${value.toFixed(1)}%` : formatPrice(value),
        },
        splitLine: {
          lineStyle: { color: "rgba(147, 166, 157, .12)", type: "dashed" },
        },
      },
      dataZoom: [
        {
          type: "inside",
          filterMode: "none",
          throttle: 50,
        },
        {
          type: "slider",
          height: 22,
          bottom: 22,
          borderColor: "transparent",
          backgroundColor: "#111a17",
          fillerColor: "rgba(222, 128, 81, .18)",
          dataBackground: {
            lineStyle: { color: "#56675f" },
            areaStyle: { color: "#26342e" },
          },
          selectedDataBackground: {
            lineStyle: { color: "#de8051" },
            areaStyle: { color: "rgba(222, 128, 81, .22)" },
          },
          handleStyle: {
            color: "#de8051",
            borderColor: "#de8051",
          },
          moveHandleStyle: { color: "#87968f" },
          textStyle: { color: "#78877f", fontSize: 9 },
        },
      ],
      series: [...mainSeries, ...averageSeries],
    };
  }, [group, metric, movingAverage, scale, smooth, style]);

  useEffect(() => {
    const element = chartElement.current;
    if (!element) return;
    const chart = echarts.init(element, undefined, { renderer: "canvas" });
    chart.setOption(option, true);
    const observer = new ResizeObserver(() => chart.resize());
    observer.observe(element);
    return () => {
      observer.disconnect();
      chart.dispose();
    };
  }, [option]);

  return (
    <article className="chart-card">
      <header className="chart-card-heading">
        <div>
          <p>{group.unit}</p>
          <h3>{group.title}</h3>
        </div>
        <span>{group.series.reduce((total, series) => total + series.points.length, 0)} points</span>
      </header>
      <div
        ref={chartElement}
        className="echart"
        role="img"
        aria-label={`Графік: ${group.title}`}
      />
    </article>
  );
}
