# Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
# This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2025 Datadog, Inc.

import os
import logging
import datadog
from ddtrace import tracer
from flask import Flask

datadog.initialize(
    statsd_host="127.0.0.1",
    statsd_port=8125,
)


app = Flask(__name__)

### Enable Datadog Logging
# FORMAT = ('%(asctime)s %(levelname)s [%(name)s] [%(filename)s:%(lineno)d] '
#           '[dd.service=%(dd.service)s dd.env=%(dd.env)s dd.version=%(dd.version)s dd.trace_id=%(dd.trace_id)s dd.span_id=%(dd.span_id)s] '
#           '- %(message)s')
log_filename = os.environ.get(
    "DD_SERVERLESS_LOG_PATH", "/shared-volume/logs/*.log"
).replace("*.log", "app.log")
os.makedirs(os.path.dirname(log_filename), exist_ok=True)

logging.basicConfig(level=logging.INFO, filename=log_filename)
logger = logging.getLogger(__name__)

@app.route("/")
@tracer.wrap(service="cloudrun-tf-python-hello", resource="wrapper-module-test")
def hello_world():
    datadog.statsd.distribution("cloudrun-py-sample-metric", 1)
    logger.info("Hello Datadog logger using Python!")
    return f"Hello Python World!"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
