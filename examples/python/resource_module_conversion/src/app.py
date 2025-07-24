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

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@app.route("/")
# @tracer.wrap(service="cloudrun-tf-python-integration", resource="hellohelp")
def hello_world():
    # datadog.statsd.distribution("cloudrun-py-sample-metric", 1)
    logger.info("Hello Datadog logger using Python!")
    return f"Hello Python World!"

if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
