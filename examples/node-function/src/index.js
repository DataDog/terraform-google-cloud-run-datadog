const tracer = require('dd-trace').init({
  logInjection: true,
});

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
  const span = tracer.startSpan('helloHttp');
  span.setTag('foo', 'bar');
  logger.info('Hello World!');
  span.finish();
  res.set('Content-Type', 'text/plain');
  res.send(`Hello ${req.query.name || req.body.name || 'World'}!`);
});
