output "app_url" {
  description = "Open this with the bridge's pairing token: <app_url>/#token=..."
  value       = "https://${var.app_hostname}"
}

output "bridge_origin" {
  description = "Tunnel hostname the Worker relays to (protected by Access)."
  value       = "https://${var.bridge_hostname}"
}

output "tunnel_token" {
  description = "TUNNEL_TOKEN for `cloudflared tunnel run` on the Mac. Keep state private."
  value       = data.cloudflare_zero_trust_tunnel_cloudflared_token.bridge.token
  sensitive   = true
}
