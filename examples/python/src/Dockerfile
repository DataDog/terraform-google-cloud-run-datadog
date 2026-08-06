# Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
# This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2025 Datadog, Inc.

FROM python:3.13-slim

WORKDIR /app/

COPY requirements.txt app.py ./
RUN pip install --no-cache-dir -r requirements.txt

EXPOSE 8080

# Apply the auto-instrumentation provided by the ddtrace dependency.
CMD ["ddtrace-run", "python", "app.py"]
