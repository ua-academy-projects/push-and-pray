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

export function createId(cryptoObject = globalThis.crypto) {
  if (typeof cryptoObject?.randomUUID === 'function') {
    return cryptoObject.randomUUID();
  }

  if (typeof cryptoObject?.getRandomValues === 'function') {
    const bytes = cryptoObject.getRandomValues(new Uint8Array(16));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    const hex = [...bytes].map(byte => byte.toString(16).padStart(2, '0')).join('');
    return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
  }

  return `rateboard-${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
}
