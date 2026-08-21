/**
 * Generic API heartbeat canary for CloudWatch Synthetics.
 *
 * Performs an HTTP(S) GET against a target URL and asserts a 2xx status
 * code. Intended for lightweight cross-account API heartbeat / uptime
 * monitoring where a full browser (Puppeteer) check is unnecessary.
 *
 * The Synthetics Node.js runtime (syn-nodejs-puppeteer-*) expects the
 * handler module to export an async `handler` function. We use the
 * `synthetics` executor's built-in HTTP step helper so the check
 * shows up as a discrete step in the canary run report, and we still
 * rely on Puppeteer's bundled `synthetics` library for logging/metrics.
 */
const synthetics = require('Synthetics');
const log = require('SyntheticsLogger');
const syntheticsConfiguration = synthetics.getConfiguration();

// The target URL is injected at deploy time via environment variable
// TARGET_URL (set on the Lambda function backing the canary). Each
// canary instance gets its own function, so this stays one URL per
// canary even though the handler code is shared.
const TARGET_URL = process.env.TARGET_URL;

const apiCanaryBlueprint = async function () {
  syntheticsConfiguration.setConfig({
    includeRequestHeaders: true,
    includeResponseHeaders: true,
    restrictedHeaders: [],
    restrictedUrlParameters: [],
  });

  if (!TARGET_URL) {
    throw new Error('TARGET_URL environment variable is not set for this canary.');
  }

  const stepConfig = {
    includeRequestHeaders: true,
    includeResponseHeaders: true,
    restrictedHeaders: [],
    restrictedUrlParameters: [],
  };

  await synthetics.executeHttpStep(
    'heartbeatCheck',
    TARGET_URL,
    (res) => {
      return new Promise((resolve, reject) => {
        const statusCode = res.statusCode;
        log.info(`Heartbeat check for ${TARGET_URL} returned status ${statusCode}`);

        if (statusCode < 200 || statusCode >= 300) {
          reject(new Error(`Heartbeat check failed: expected 2xx, got ${statusCode}`));
          return;
        }

        // Drain the response body so the request is considered complete.
        res.on('data', () => {});
        res.on('end', () => resolve());
      });
    },
    stepConfig
  );
};

exports.handler = async () => {
  return await apiCanaryBlueprint();
};
