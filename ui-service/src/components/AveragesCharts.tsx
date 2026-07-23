import {
  Area,
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  ComposedChart,
  Legend,
  Line,
  LineChart,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import type { ChartData } from "../types/chart";
import type { PeriodStatistics } from "../types/statistics";
import { formatShortDate } from "../utils/dateFormat";
import { conditionBucketInfo } from "../utils/conditionBucket";
import styles from "./AveragesCharts.module.css";

interface AveragesChartsProps {
  data: ChartData;
  stats: PeriodStatistics;
}

const GRID_COLOR = "var(--chart-grid)";
const TICK_STYLE = { fill: "var(--text-muted)", fontSize: 11 };
const TOOLTIP_STYLE = {
  background: "var(--chart-surface)",
  border: "1px solid var(--glass-border)",
  borderRadius: 10,
  fontSize: 12,
  color: "var(--text-primary)",
};

function Panel({ title, wide, empty, children }: { title: string; wide?: boolean; empty?: boolean; children: React.ReactNode }) {
  return (
    <div className={`${styles.panel} ${wide ? styles.wide : ""}`}>
      <div className={styles.title}>{title}</div>
      {empty ? <div className={styles.empty}>No data for this range</div> : <div className={styles.chartBox}>{children}</div>}
    </div>
  );
}

/** All five Averages charts, computed from PostgreSQL-backed statistics/chart endpoints.
 * Colors are fixed slots from the validated categorical palette (--series-1..5), assigned in a
 * stable order per chart -- never re-cycled based on which series happen to be present. */
export function AveragesCharts({ data, stats }: AveragesChartsProps) {
  const temperaturePoints = data.temperature.map((point) => ({
    ...point,
    band: point.maximum - point.minimum,
  }));
  const conditionData = (["clear", "cloudy", "rain", "snow"] as const)
    .map((bucket) => ({
      bucket,
      count: bucket === "clear" ? stats.clear_days : bucket === "cloudy" ? stats.cloudy_days : bucket === "rain" ? stats.rainy_days : stats.snowy_days,
      ...conditionBucketInfo(bucket),
    }))
    .filter((entry) => entry.count > 0);

  return (
    <div className={styles.grid}>
      <Panel title="Temperature (avg, with daily min–max band)" wide empty={temperaturePoints.length === 0}>
        <ResponsiveContainer>
          <ComposedChart data={temperaturePoints}>
            <CartesianGrid stroke={GRID_COLOR} vertical={false} />
            <XAxis dataKey="date" tickFormatter={formatShortDate} tick={TICK_STYLE} minTickGap={24} />
            <YAxis tick={TICK_STYLE} unit="°" width={40} />
            <Tooltip contentStyle={TOOLTIP_STYLE} labelFormatter={(label) => formatShortDate(String(label))} />
            <Legend wrapperStyle={{ fontSize: 12, color: "var(--text-secondary)" }} />
            <Area dataKey="minimum" stackId="band" stroke="none" fill="transparent" legendType="none" isAnimationActive={false} />
            <Area
              dataKey="band"
              stackId="band"
              name="Daily min–max"
              stroke="none"
              fill="var(--series-1)"
              fillOpacity={0.15}
              isAnimationActive={false}
            />
            <Line dataKey="average" name="Average" stroke="var(--series-1)" strokeWidth={2} dot={false} isAnimationActive={false} />
          </ComposedChart>
        </ResponsiveContainer>
      </Panel>

      <Panel title="Humidity (avg)" empty={data.humidity.every((point) => point.average === null)}>
        <ResponsiveContainer>
          <ComposedChart data={data.humidity}>
            <CartesianGrid stroke={GRID_COLOR} vertical={false} />
            <XAxis dataKey="date" tickFormatter={formatShortDate} tick={TICK_STYLE} minTickGap={24} />
            <YAxis tick={TICK_STYLE} unit="%" width={40} domain={[0, 100]} />
            <Tooltip contentStyle={TOOLTIP_STYLE} labelFormatter={(label) => formatShortDate(String(label))} />
            <Area
              dataKey="average"
              name="Humidity"
              stroke="var(--series-2)"
              strokeWidth={2}
              fill="var(--series-2)"
              fillOpacity={0.18}
              connectNulls
              isAnimationActive={false}
            />
          </ComposedChart>
        </ResponsiveContainer>
      </Panel>

      <Panel title="Precipitation (total)" empty={data.precipitation.length === 0}>
        <ResponsiveContainer>
          <BarChart data={data.precipitation}>
            <CartesianGrid stroke={GRID_COLOR} vertical={false} />
            <XAxis dataKey="date" tickFormatter={formatShortDate} tick={TICK_STYLE} minTickGap={24} />
            <YAxis tick={TICK_STYLE} unit="mm" width={40} />
            <Tooltip contentStyle={TOOLTIP_STYLE} labelFormatter={(label) => formatShortDate(String(label))} />
            <Bar dataKey="total" name="Precipitation" fill="var(--series-3)" radius={[4, 4, 0, 0]} isAnimationActive={false} />
          </BarChart>
        </ResponsiveContainer>
      </Panel>

      <Panel title="Wind speed (avg / max)" empty={data.wind.every((point) => point.average === null && point.maximum === 0)}>
        <ResponsiveContainer>
          <LineChart data={data.wind}>
            <CartesianGrid stroke={GRID_COLOR} vertical={false} />
            <XAxis dataKey="date" tickFormatter={formatShortDate} tick={TICK_STYLE} minTickGap={24} />
            <YAxis tick={TICK_STYLE} unit=" km/h" width={52} />
            <Tooltip contentStyle={TOOLTIP_STYLE} labelFormatter={(label) => formatShortDate(String(label))} />
            <Legend wrapperStyle={{ fontSize: 12, color: "var(--text-secondary)" }} />
            <Line dataKey="average" name="Average" stroke="var(--series-1)" strokeWidth={2} dot={false} connectNulls isAnimationActive={false} />
            <Line dataKey="maximum" name="Maximum" stroke="var(--series-4)" strokeWidth={2} dot={false} isAnimationActive={false} />
          </LineChart>
        </ResponsiveContainer>
      </Panel>

      <Panel title="Condition distribution" empty={conditionData.length === 0}>
        <ResponsiveContainer>
          <PieChart>
            <Tooltip contentStyle={TOOLTIP_STYLE} />
            <Legend wrapperStyle={{ fontSize: 12, color: "var(--text-secondary)" }} />
            <Pie data={conditionData} dataKey="count" nameKey="label" innerRadius="55%" outerRadius="85%" isAnimationActive={false}>
              {conditionData.map((entry) => (
                <Cell key={entry.bucket} fill={entry.color} />
              ))}
            </Pie>
          </PieChart>
        </ResponsiveContainer>
      </Panel>
    </div>
  );
}
