'use strict';
const https = require('node:https');

// Keep response bodies out of artifacts/logs. A bounded read also protects the runner
// against accidentally requesting a large page instead of the health endpoint.
function checkHealth(url) {
  return new Promise((resolve, reject) => {
    const request = https.get(url, { timeout: 15000 }, response => {
      let body = '';
      let size = 0;
      response.on('data', chunk => {
        size += chunk.length;
        if (size > 65536) {
          response.destroy(new Error('Health response exceeds 64 KiB'));
          return;
        }
        body += chunk.toString('utf8');
      });
      response.on('error', reject);
      response.on('end', () => {
        try {
          if (response.statusCode !== 200) throw new Error(`Health HTTP ${response.statusCode}`);
          let result;
          try { result = JSON.parse(body); } catch { throw new Error('Health response is not JSON'); }
          if (result.status !== 'ok' || result.history !== 'connected' || result.sessions !== 'redis') {
            throw new Error('Health dependencies are not ready');
          }
          resolve();
        } catch (error) { reject(error); }
      });
    });
    request.on('timeout', () => request.destroy(new Error('Health request timed out')));
    request.on('error', reject);
  });
}

exports.handler = async (_event, context) => {
  // The engine chooses its log-group suffix. Set retention on its own group after
  // Lambda creates it, avoiding a Terraform create-vs-first-run race.
  const { CloudWatchLogsClient, PutRetentionPolicyCommand } = require('@aws-sdk/client-cloudwatch-logs');
  await new CloudWatchLogsClient({}).send(new PutRetentionPolicyCommand({
    logGroupName: context.logGroupName,
    retentionInDays: Number(process.env.LOG_RETENTION_DAYS)
  }));
  const synthetics = require('@aws/synthetics-puppeteer');
  const url = new URL(process.env.HEALTH_URL);
  if (url.protocol !== 'https:' || url.username || url.password) {
    throw new Error('HEALTH_URL must be HTTPS without credentials');
  }
  await synthetics.executeStep('health', () => checkHealth(url));
  if (process.env.BROWSER_ENABLED === 'true') {
    synthetics.getConfiguration().setConfig({
      screenshotOnStepStart: false, screenshotOnStepSuccess: false,
      screenshotOnStepFailure: true, includeRequestHeaders: false,
      includeResponseHeaders: false, includeRequestBody: false, includeResponseBody: false
    });
    const page = await synthetics.getPage();
    // Each run creates its own anonymous Redis session, never an administrator session.
    await page.deleteCookie(...await page.cookies(url.origin));
    await browserJourney(page, url.origin, (name, fn) => synthetics.executeStep(name, fn));
  }
};
exports.checkHealth = checkHealth;

async function browserJourney(page, origin, step) {
  const errors = [];
  page.on('pageerror', () => errors.push('JavaScript error'));
  page.setDefaultTimeout(15000);
  await step('render-charts', async () => {
    const response = await page.goto(origin, { waitUntil: 'networkidle0', timeout: 20000 });
    if (!response || response.status() !== 200) throw new Error('UI navigation failed');
    await page.waitForFunction(() => {
      const canvases = [...document.querySelectorAll('canvas')];
      return document.querySelectorAll('.instrument-list input[type=checkbox]').length === 3 &&
        canvases.some(canvas => canvas.width > 0 && canvas.height > 0) &&
        Number(document.querySelector('.point-count strong')?.textContent) > 0;
    });
  });
  async function clickButton(text) {
    await page.evaluate(label => {
      const button = [...document.querySelectorAll('button')].find(item => item.textContent.trim() === label);
      if (!button) throw new Error('Missing interaction control');
      button.click();
    }, text);
  }
  await step('save-preferences', async () => {
    const saved = page.waitForResponse(response =>
      new URL(response.url()).pathname === '/api/session/preferences' &&
      response.request().method() === 'PUT' && response.status() === 200);
    await clickButton('Clear');
    await saved;
    await page.waitForFunction(() => document.querySelectorAll('.instrument-list input:checked').length === 0);
    await page.reload({ waitUntil: 'networkidle0' });
    await page.waitForFunction(() => document.querySelectorAll('.instrument-list input').length === 3 &&
      document.querySelectorAll('.instrument-list input:checked').length === 0);
  });
  await step('restore-chart-selection', async () => {
    const saved = page.waitForResponse(response =>
      new URL(response.url()).pathname === '/api/session/preferences' &&
      response.request().method() === 'PUT' && response.status() === 200);
    await clickButton('Select all');
    await saved;
    await page.waitForFunction(() => document.querySelectorAll('.instrument-list input:checked').length === 3 &&
      document.querySelector('canvas') !== null);
    if (errors.length) throw new Error('UI JavaScript errors');
  });
}
exports.browserJourney = browserJourney;
