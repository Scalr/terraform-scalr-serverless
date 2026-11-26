variable "agent_pool_name" {
  description = "Name of the agent pool"
  type        = string
  default     = "webhook-agent-pool"
}

variable "scalr_url" {
  description = "Scalr URL the agent connects to. Defaults to https://<account>.scalr.io"
  type        = string
  default     = null
}

# Future inputs for API Gateway integration
variable "webhook_url" {
  type        = string
  description = "API Gateway webhook URL (optional, for future integration)"
  default     = null
}

variable "webhook_headers" {
  type = list(object({
    name      = string
    value     = string
    sensitive = bool
  }))
  description = "Headers for webhook requests with sensitivity control"
  default     = []
  sensitive   = true
}
