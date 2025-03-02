variable "dev_region" {
  type        = string
  default     = "eu-west-2"
  description = "Region for dev infrastructure"
}

#variable "prod_region" {
#    type = string
#    default = "eu-west-1"
#    description = "Region for prod infrastructure"
#}

variable "name" {
  type        = string
  default     = "portal-api"
  description = "The name of the solution"
}
