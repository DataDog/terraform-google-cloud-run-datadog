import os
import logging
# import datadog
# from ddtrace import tracer
from flask import Flask

# datadog.initialize(
#     statsd_host="127.0.0.1",
#     statsd_port=8125,
# )


app = Flask(__name__)

### Enable Datadog Logging
log_filename = os.environ.get(
    "DD_SERVERLESS_LOG_PATH", "/shared-volume/logs/*.log"
).replace("*.log", "app.log")
os.makedirs(os.path.dirname(log_filename), exist_ok=True)

logging.basicConfig(level=logging.INFO, filename=log_filename)
### END Enable Datadog Logging

# logging.basicConfig(level=logging.INFO) #line to replace if originally logigng without datadog
logger = logging.getLogger(__name__)

@app.route("/")
# @tracer.wrap(service="cloudrun-tf-python-hello", resource="wrapper-module-test")
def hello_world():
    # datadog.statsd.distribution("cloudrun-py-sample-metric", 1)
    logger.info("Hello Datadog logger using Python!")
    return f"Hello Python World!"

if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
