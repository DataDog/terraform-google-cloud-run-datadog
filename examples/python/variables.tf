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


//google resource
variable "name" {
  type        = string
  description = "The name of the Cloud Run service"
  default     = "cloud-run-tf-example"
  nullable    = false
}

variable "image" {
  type        = string
  description = "The image to deploy the service to"
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
  nullable    = false
}

//datadog values

variable "datadog_api_key" {
  type        = string
  description = "The api key for datadog"
  nullable    = false
}
