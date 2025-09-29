# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache 2.0 License.

# This product includes software developped at
# Datadog (https://www.datadoghq.com/)
# Copyright 2025-present Datadog, Inc.

FROM ruby:3.3-slim

# Install build dependencies and ca-certificates
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile .
RUN bundle install

ENV PORT=8080
EXPOSE 8080

COPY . .

CMD ["bundle", "exec", "ruby", "app.rb"]
