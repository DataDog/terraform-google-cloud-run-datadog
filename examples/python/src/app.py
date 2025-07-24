import os
# import logging
# import datadog
# from ddtrace import tracer
from flask import Flask

# datadog.initialize(
#     statsd_host="127.0.0.1",
#     statsd_port=8125,
# )


app = Flask(__name__)

@app.route("/")
# @tracer.wrap(service="cloudrun-tf-python-integration", resource="hellohelp")
def hello_world():
    # datadog.statsd.distribution("cloudrun-py-sample-metric", 1)
    # logger.info("Hello Datadog logger using Python!")
    return f"Hello Python World!"

if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))





# variable "description" {
#   type        = optional(string, null)
#   description = "The description of the Cloud Run service, 512 chars max"
# }

# variable "labels" {
#   type        = optional(map(string), {})
#   description = "The labels of the Cloud Run service, present only in current configuration"
# }

# variable "annotations" {
#   type        = optional(map(string), {})
#   description = "The annotations of the Cloud Run service"
# }

# variable "client" {
#   type        = optional(string, null)
#   description = "Identifier for API client"
# }

# variable "client_version" {
#   type        = optional(string, null)
#   description = "Version identifier for API client"
# }

# variable "ingress" {
#   type        = string
#   description = "The ingress of the Cloud Run service"
#   validation {
#     condition     = contains(["INGRESS_TRAFFIC_ALL", "INGRESS_TRAFFIC_INTERNAL_ONLY", "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"], value)
#     error_message = "Invalid ingress value. Allowed values are \"INGRESS_TRAFFIC_ALL\", \"INGRESS_TRAFFIC_INTERNAL_ONLY\", or \"INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER\"."
#   }
#   default = "INGRESS_TRAFFIC_ALL"
# }

# variable "launch_stage" {
#   type        = string
#   description = "The launch stage as defined by Google Cloud Platform Launch Stages. Cloud Run supports ALPHA, BETA, and GA. If no value is specified, GA is assumed. Set the launch stage to a preview stage on input to allow use of preview features in that stage. On read (or output), describes whether the resource uses preview features. For example, if ALPHA is provided as input, but only BETA and GA-level features are used, this field will be BETA on output. Possible values are: UNIMPLEMENTED, PRELAUNCH, EARLY_ACCESS, ALPHA, BETA, GA, DEPRECATED"
#   validation {
#     condition     = contains(["UNIMPLEMENTED", "PRELAUNCH", "EARLY_ACCESS", "ALPHA", "BETA", "GA", "DEPRECATED"], value)
#     error_message = "Invalid launch stage value. Allowed values are \"UNIMPLEMENTED\", \"PRELAUNCH\", \"EARLY_ACCESS\", \"ALPHA\", \"BETA\", \"GA\", or \"DEPRECATED\"."
#   }
#   default = "GA"
# }

# variable "binary_authorization" {
#   type        = optional(object({
#     breakglass_justification = optional(string, null)
#     policy = optional(string, null)
#     use_default = optional(bool, null)
#   }), null)
#   description = "Settings for the Binary Authorization feature."
# }

# variable "custom_audiences" {
#   type        = optional(list(string), null)
#   description = "One or more custom audiences that you want this service to support. Specify each custom audience as the full URL in a string. The custom audiences are encoded in the token and used to authenticate requests. For more information, see https://cloud.google.com/run/docs/configuring/custom-audiences."
# }

# variable "scaling" {
#   type        = optional(object({
#     min_instance_count = optional(number, null)
#     max_instance_count = optional(number, null)
#     scaling_mode = optional(string, null)
#   }), null)
# }
# //structs






# //service
# variable "project" {
#   type        = optional(string, null)
#   description = "The project ID to deploy the service to"
# }