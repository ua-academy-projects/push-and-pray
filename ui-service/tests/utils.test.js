import test from 'node:test';
import assert from 'node:assert/strict';
import { chosenTheme, formatMoney, percentSeries } from '../public/js/utils.js';

test('percentage series starts at zero', () => {
  assert.deepEqual(percentSeries([{ value: '100' }, { value: '110' }]).map(x => x.value), ['0.0000', '10.0000']);
});

test('saved theme overrides system preference', () => {
  assert.equal(chosenTheme('light', true), 'light');
  assert.equal(chosenTheme(null, true), 'dark');
});

test('rates are always displayed with two decimal places', () => {
  assert.match(formatMoney('0.123456', 'USD'), /0,12\sUSD/);
  assert.match(formatMoney('42', 'UAH'), /42,00\sUAH/);
});
