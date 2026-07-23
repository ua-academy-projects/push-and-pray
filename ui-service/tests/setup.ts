import "@testing-library/jest-dom/vitest";

// Recharts' ResponsiveContainer measures its wrapper via ResizeObserver and
// offsetWidth/offsetHeight, neither of which jsdom implements -- without this, every chart
// renders at 0x0 and no <svg> ever appears, even with real data.
class MockResizeObserver {
  observe() {}
  unobserve() {}
  disconnect() {}
}
// eslint-disable-next-line @typescript-eslint/no-explicit-any
(globalThis as any).ResizeObserver = MockResizeObserver;

Object.defineProperty(HTMLElement.prototype, "offsetWidth", { configurable: true, value: 600 });
Object.defineProperty(HTMLElement.prototype, "offsetHeight", { configurable: true, value: 300 });
HTMLElement.prototype.getBoundingClientRect = () =>
  ({ width: 600, height: 300, top: 0, left: 0, bottom: 300, right: 600, x: 0, y: 0, toJSON() {} }) as DOMRect;
