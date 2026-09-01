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
const https = require('https');
const tls = require('tls');
const syntheticsConfiguration = synthetics.getConfiguration();

// The target URL is injected at deploy time via environment variable
// TARGET_URL (set on the Lambda function backing the canary). Each
// canary instance gets its own function, so this stays one URL per
// canary even though the handler code is shared.
const TARGET_URL = process.env.TARGET_URL;

// Some targets serve their TLS chain without the intermediate cert
// (leaf certificate followed directly by the root CA, skipping
// "DigiCert Global G2 TLS RSA SHA256 2020 CA1"). Browsers complete the
// chain themselves via AIA fetching and never notice; Node's TLS stack
// does not, so this heartbeat fails strict verification against an
// otherwise-valid certificate. Extending the trusted CA set with this
// specific, publicly-issued intermediate - rather than disabling
// verification - closes that gap without weakening validation for any
// target: it's additive trust for a real CA already anchored to a root
// Node trusts, not a bypass. Harmless for targets that already send the
// full chain correctly.
const DIGICERT_GLOBAL_G2_TLS_RSA_SHA256_2020_CA1 = `-----BEGIN CERTIFICATE-----
MIIEyDCCA7CgAwIBAgIQDPW9BitWAvR6uFAsI8zwZjANBgkqhkiG9w0BAQsFADBh
MQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3
d3cuZGlnaWNlcnQuY29tMSAwHgYDVQQDExdEaWdpQ2VydCBHbG9iYWwgUm9vdCBH
MjAeFw0yMTAzMzAwMDAwMDBaFw0zMTAzMjkyMzU5NTlaMFkxCzAJBgNVBAYTAlVT
MRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxMzAxBgNVBAMTKkRpZ2lDZXJ0IEdsb2Jh
bCBHMiBUTFMgUlNBIFNIQTI1NiAyMDIwIENBMTCCASIwDQYJKoZIhvcNAQEBBQAD
ggEPADCCAQoCggEBAMz3EGJPprtjb+2QUlbFbSd7ehJWivH0+dbn4Y+9lavyYEEV
cNsSAPonCrVXOFt9slGTcZUOakGUWzUb+nv6u8W+JDD+Vu/E832X4xT1FE3LpxDy
FuqrIvAxIhFhaZAmunjZlx/jfWardUSVc8is/+9dCopZQ+GssjoP80j812s3wWPc
3kbW20X+fSP9kOhRBx5Ro1/tSUZUfyyIxfQTnJcVPAPooTncaQwywa8WV0yUR0J8
osicfebUTVSvQpmowQTCd5zWSOTOEeAqgJnwQ3DPP3Zr0UxJqyRewg2C/Uaoq2yT
zGJSQnWS+Jr6Xl6ysGHlHx+5fwmY6D36g39HaaECAwEAAaOCAYIwggF+MBIGA1Ud
EwEB/wQIMAYBAf8CAQAwHQYDVR0OBBYEFHSFgMBmx9833s+9KTeqAx2+7c0XMB8G
A1UdIwQYMBaAFE4iVCAYlebjbuYP+vq5Eu0GF485MA4GA1UdDwEB/wQEAwIBhjAd
BgNVHSUEFjAUBggrBgEFBQcDAQYIKwYBBQUHAwIwdgYIKwYBBQUHAQEEajBoMCQG
CCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wQAYIKwYBBQUHMAKG
NGh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEdsb2JhbFJvb3RH
Mi5jcnQwQgYDVR0fBDswOTA3oDWgM4YxaHR0cDovL2NybDMuZGlnaWNlcnQuY29t
L0RpZ2lDZXJ0R2xvYmFsUm9vdEcyLmNybDA9BgNVHSAENjA0MAsGCWCGSAGG/WwC
ATAHBgVngQwBATAIBgZngQwBAgEwCAYGZ4EMAQICMAgGBmeBDAECAzANBgkqhkiG
9w0BAQsFAAOCAQEAkPFwyyiXaZd8dP3A+iZ7U6utzWX9upwGnIrXWkOH7U1MVl+t
wcW1BSAuWdH/SvWgKtiwla3JLko716f2b4gp/DA/JIS7w7d7kwcsr4drdjPtAFVS
slme5LnQ89/nD/7d+MS5EHKBCQRfz5eeLjJ1js+aWNJXMX43AYGyZm0pGrFmCW3R
bpD0ufovARTFXFZkAdl9h6g4U5+LXUZtXMYnhIHUfoyMo5tS58aI7Dd8KvvwVVo4
chDYABPPTHPbqjc1qCmBaZx2vN4Ye5DUys/vZwP9BFohFrH/6j/f3IL16/RZkiMN
JCqVJUzKoZHm1Lesh3Sz8W2jmdv51b2EQJ8HmA==
-----END CERTIFICATE-----`;

const httpsAgentWithExtraTrust = new https.Agent({
  ca: [...tls.rootCertificates, DIGICERT_GLOBAL_G2_TLS_RSA_SHA256_2020_CA1],
});

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

  // Pass a requestOptions object (rather than the plain URL string) only
  // for https targets, so the extra-trust agent above is attached
  // without changing behavior for any http:// target.
  const parsedUrl = new URL(TARGET_URL);
  const httpStepTarget =
    parsedUrl.protocol === 'https:'
      ? {
          hostname: parsedUrl.hostname,
          path: parsedUrl.pathname + parsedUrl.search,
          port: parsedUrl.port || 443,
          protocol: parsedUrl.protocol,
          method: 'GET',
          agent: httpsAgentWithExtraTrust,
        }
      : TARGET_URL;

  await synthetics.executeHttpStep(
    'heartbeatCheck',
    httpStepTarget,
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
