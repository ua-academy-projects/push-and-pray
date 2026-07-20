export function percentSeries(points) {
  if (!points.length) return [];
  const first = Number(points[0].value);
  return points.map(point => ({ ...point, value: first ? ((Number(point.value) / first - 1) * 100).toFixed(4) : '0' }));
}

export function chosenTheme(saved, systemDark) { return saved || (systemDark ? 'dark' : 'light'); }

export function formatMoney(value, currency) {
  const number = Number(value);
  return new Intl.NumberFormat('uk-UA', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(number) + ` ${currency}`;
}
