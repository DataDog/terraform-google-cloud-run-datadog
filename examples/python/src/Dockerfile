# Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
# This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2025 Datadog, Inc.

FROM python:3.13-slim AS runtime
WORKDIR /app/

COPY requirements.txt app.py ./
RUN pip install --no-cache-dir -r requirements.txt

EXPOSE 8080
CMD ["python", "app.py"]

# SSI on: stop here; the module sets PYTHONPATH=/datadog-lib (do not pip-install
# ddtrace — injection aborts if it is already present).
FROM runtime AS ssi

# SSI off (default): install ddtrace for the manual APM fallback in app.py.
FROM runtime AS manual
RUN pip install --no-cache-dir ddtrace==4.11.1

FROM manual
