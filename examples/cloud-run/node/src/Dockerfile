# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache 2.0 License.

# This product includes software developped at
# Datadog (https://www.datadoghq.com/)
# Copyright 2025-present Datadog, Inc.

FROM node:22-slim

WORKDIR /app

COPY package.json .
RUN npm install

COPY . .

ENV PORT=8080
EXPOSE 8080

ENV NODE_OPTIONS="--require dd-trace/init"

CMD ["node", "index.js"]
