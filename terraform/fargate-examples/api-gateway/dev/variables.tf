variable "region" {
  type        = string
  description = "AWS region"
}

variable "name" {
  type        = string
  description = "Name for the resources"
}

variable "stage_name" {
  type        = string
  description = "Name of the stage for the API gateway"
  default     = "dev"
}

variable "lb_service_url" {
  type        = string
  description = "URL of the load balancer service"
}
