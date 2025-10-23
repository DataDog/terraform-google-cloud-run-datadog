# Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
# This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2025 Datadog, Inc.

//provider

variable "project" {
  type        = string
  description = "The project ID to deploy the service to"
  nullable    = false
}

variable "region" {
  type        = string
  description = "The region to deploy the service to (used in example for both google provider region and cloud run resource location)"
  nullable    = false
}



//datadog values

variable "datadog_api_key" {
  type        = string
  description = "The api key for datadog"
  nullable    = false
}
