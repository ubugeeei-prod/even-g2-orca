variable "account_id" {
  type        = string
  description = "Cloudflare account that owns the Worker, Tunnel and Access application."
}

variable "zone_id" {
  type        = string
  description = "DNS zone containing app_hostname and bridge_hostname."
}

variable "app_hostname" {
  type        = string
  description = "Public hostname of the phone app (Worker custom domain), e.g. orca.example.com."
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9.-]+$", var.app_hostname))
    error_message = "Use a DNS hostname without a scheme or path."
  }
}

variable "bridge_hostname" {
  type        = string
  description = "Tunnel hostname in front of the Mac bridge, e.g. orca-bridge.example.com. Only the Worker can pass its Access policy."
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9.-]+$", var.bridge_hostname))
    error_message = "Use a DNS hostname without a scheme or path."
  }
}

variable "bridge_service" {
  type        = string
  description = "Loopback HTTP listener of the bridge on the Mac running cloudflared."
  default     = "http://127.0.0.1:3210"
  validation {
    condition     = can(regex("^http://(127\\.0\\.0\\.1|localhost):[0-9]+$", var.bridge_service))
    error_message = "The tunnel must forward to a loopback listener."
  }
}

variable "dist_dir" {
  type        = string
  description = "Output of scripts/build.sh or `nix build` (contains web/ and worker/). Empty means ../dist."
  default     = ""
}

variable "allowed_origins" {
  type        = string
  description = "Comma-separated extra browser origins allowed to call the API (for a separately hosted package). Empty means same origin only."
  default     = ""
  validation {
    condition     = !strcontains(var.allowed_origins, "*")
    error_message = "Wildcard origins are not allowed."
  }
}

variable "resource_name" {
  type        = string
  description = "Name of the Worker and prefix of Tunnel / Access resources."
  default     = "even-g2-orca"
}

variable "compatibility_date" {
  type        = string
  description = "Workers runtime compatibility date."
  default     = "2026-09-01"
}

variable "service_token_duration" {
  type        = string
  description = "Lifetime of the Worker's Access service token. Re-apply before it expires."
  default     = "8760h"
}
