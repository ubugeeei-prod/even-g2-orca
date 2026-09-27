variable "account_id" {
  type        = string
  description = "Cloudflare account containing the Worker, Tunnel, and Access application."
}

variable "zone_id" {
  type        = string
  description = "Cloudflare DNS zone containing bridge_hostname."
}

variable "bridge_hostname" {
  type        = string
  description = "Private origin hostname, for example orca-bridge.example.com."
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9.-]+$", var.bridge_hostname))
    error_message = "Use a DNS hostname without a scheme or path."
  }
}

variable "bridge_service" {
  type        = string
  description = "Loopback HTTP origin on the Mac running cloudflared."
  default     = "http://127.0.0.1:3210"
  validation {
    condition     = can(regex("^http://(127\\.0\\.0\\.1|localhost):[0-9]+$", var.bridge_service))
    error_message = "Bind the tunnel to a loopback HTTP listener."
  }
}

variable "resource_name" {
  type        = string
  description = "Name prefix for Tunnel and Access resources."
  default     = "even-g2-orca"
}

variable "service_token_duration" {
  type        = string
  description = "Access service credential lifetime; rotate Wrangler secrets before expiry."
  default     = "8760h"
}
