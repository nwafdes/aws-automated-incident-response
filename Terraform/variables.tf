variable "N8N_WEBHOOK_URL" {
  description = " pass the webhook url here"
  type        = string
  sensitive   = true
}

variable "file_name" {
  type = string
  default = "Security_audit_bot"
}