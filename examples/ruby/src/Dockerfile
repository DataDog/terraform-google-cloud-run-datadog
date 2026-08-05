# Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
# This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2025 Datadog, Inc.

FROM ruby:3.3-slim AS runtime

# Install build dependencies and ca-certificates
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential=12.12 \
    ca-certificates=20250419 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock* ./

RUN bundle install --jobs 4 --retry 3

ENV PORT=8080
EXPOSE 8080

COPY . .

CMD ["bundle", "exec", "ruby", "app.rb"]

# SSI on: stop here; the module sets RUBYOPT to load /datadog-lib/auto_inject.
FROM runtime AS ssi

# SSI off (default): install the datadog gem for the manual fallback in app.rb.
FROM runtime AS manual
RUN bundle add datadog --require=datadog/auto_instrument && \
    bundle install --jobs 4 --retry 3

FROM manual
