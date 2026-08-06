// Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
// This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2025 Datadog, Inc.

// Manual APM fallback when SSI (datadog_apm_instrumentation) is disabled.
const ssiInjected = (process.env.NODE_OPTIONS || '').includes('dd-trace');
const tracer = ssiInjected ? null : require('dd-trace').init({ logInjection: true });

const functions = require('@google-cloud/functions-framework');
const rawLogPath = process.env.DD_SERVERLESS_LOG_PATH;
const LOG_FILE = rawLogPath && rawLogPath !== '' ? rawLogPath.replace('*.log', 'app.log') : '/shared-volume/logs/app.log';
console.log('LOG_FILE: ', LOG_FILE);


const { createLogger, format, transports } = require('winston');

const logger = createLogger({
  level: 'info',
  exitOnError: false,
  format: format.json(),
  transports: [
    new transports.Console(),
    new transports.File({ filename: LOG_FILE }),
  ]
});

functions.http('helloHttp', (req, res) => {
  const handle = () => {
    logger.info('Hello World!');
    res.set('Content-Type', 'text/plain');
    res.send(`Hello ${req.query.name || req.body?.name || 'World'}!`);
  };

  // tracer.trace activates the span, so the log line above picks up the trace id. Under
  // SSI the preloaded tracer already traces the request.
  return tracer ? tracer.trace('helloHttp', handle) : handle();
});
