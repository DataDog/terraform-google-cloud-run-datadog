// Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
// This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2025 Datadog, Inc.

// Unless explicitly stated otherwise all files in this repository are licensed
// under the Apache 2.0 License.

// This product includes software developped at
// Datadog (https://www.datadoghq.com/)
// Copyright 2025-present Datadog, Inc.

const rawLogPath = process.env.DD_SERVERLESS_LOG_PATH;
const LOG_FILE = rawLogPath && rawLogPath !== '' ? rawLogPath.replace('*.log', 'app.log') : '/shared-volume/logs/app.log';
require('dd-trace').init({
  logInjection: true,
});

const express = require('express');
const helmet = require('helmet');
const app = express();
app.use(helmet());

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

const port = 8080;

app.get('/', (req, res) => {
  logger.info('Hello Datadog logger using Node!');
  res.status(200).send('Hello Node World!');
});

app.listen(port, '0.0.0.0', () => {
  logger.info(`Server listening on 0.0.0.0:${port}`);
});

logger.info(`Starting server on port ${port}`);
