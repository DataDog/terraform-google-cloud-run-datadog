//provider

variable "project" {
  type        = string
  description = "The project ID to deploy the service to"
}

variable "region" {
  type        = string
  description = "The region to deploy the service to"
}


//google resource
variable "name" {
  type        = string
  description = "The name of the Cloud Run service"
  default     = "cloud-run-tf-python-test"
}

variable "location" {
  type        = string
  description = "The region to deploy the service to"
}

variable "image" {
  type        = string
  description = "The image to deploy the service to"
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

//datadog values

variable "datadog_api_key" {
  type        = string
  description = "The api key for datadog"
}
