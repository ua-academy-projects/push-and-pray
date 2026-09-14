'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const https = require('node:https');
const { EventEmitter } = require('node:events');
const { PassThrough } = require('node:stream');
const { checkHealth } = require('./health');

async function withResponse(status, body, action) {
  const original = https.get;
  https.get = (_url, _options, callback) => {
    const request = new EventEmitter();
    request.destroy = error => request.emit('error', error);
    process.nextTick(() => {
      const response = new PassThrough();
      response.statusCode = status;
      callback(response);
      response.end(body);
    });
    return request;
  };
  try { await action(); } finally { https.get = original; }
}

test('healthy dependencies pass', async () => {
  await withResponse(200, JSON.stringify({status:'ok',history:'connected',sessions:'redis'}), () => checkHealth('https://example.com/health'));
});
test('HTTP failures and redirects fail even with a healthy body', async () => {
  for (const status of [301,500,503]) {
    await withResponse(status, '{}', () => assert.rejects(checkHealth('https://example.com'), /Health HTTP/));
  }
});
test('HTTP 200 alone is insufficient', async () => {
  for (const body of ['{}','{"status":"ok","history":"down","sessions":"redis"}']) {
    await withResponse(200, body, () => assert.rejects(checkHealth('https://example.com'), /dependencies/));
  }
});
test('invalid JSON error does not expose response body', async () => {
  await withResponse(200, 'private-response-content', () => assert.rejects(checkHealth('https://example.com'), { message: 'Health response is not JSON' }));
});
test('large responses fail', async () => {
  await withResponse(200, 'x'.repeat(65537), () => assert.rejects(checkHealth('https://example.com'), /64 KiB/));
});
test('transport failures fail', async () => {
  const original = https.get;
  https.get = () => {
    const request = new EventEmitter();
    process.nextTick(() => request.emit('error', new Error('connection failed')));
    return request;
  };
  try { await assert.rejects(checkHealth('https://example.com'), /connection failed/); }
  finally { https.get = original; }
});
