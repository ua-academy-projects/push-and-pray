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
          if (result.status !== 'ok' || result.history !== 'connected' || result.sessions !== 'postgresql') {
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
};
exports.checkHealth = checkHealth;
