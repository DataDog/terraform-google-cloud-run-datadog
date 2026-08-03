# Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
# This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2025 Datadog, Inc.

FROM node:22-slim AS runtime
WORKDIR /app

COPY package.json .
RUN npm install

COPY . .

ENV PORT=8080
EXPOSE 8080
CMD ["node", "index.js"]

# SSI on: stop here; the module sets NODE_OPTIONS for /datadog-lib.
FROM runtime AS ssi

# SSI off (default): install dd-trace and auto-load it via NODE_OPTIONS.
FROM runtime AS manual
RUN npm install dd-trace@^5.118.0
ENV NODE_OPTIONS="--require dd-trace/init"

FROM manual
