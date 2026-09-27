output "bridge_origin" {
  description = "Set this nonsecret value as Wrangler's ORCA_BRIDGE_ORIGIN."
  value       = "https://${var.bridge_hostname}"
}

output "tunnel_token" {
  description = "Mac cloudflared TUNNEL_TOKEN. Keep Terraform state private."
  value       = data.cloudflare_zero_trust_tunnel_cloudflared_token.orca.token
  sensitive   = true
}

output "access_client_id" {
  description = "Pipe into wrangler secret put ACCESS_CLIENT_ID."
  value       = cloudflare_zero_trust_access_service_token.worker.client_id
  sensitive   = true
}

output "access_client_secret" {
  description = "Pipe into wrangler secret put ACCESS_CLIENT_SECRET."
  value       = cloudflare_zero_trust_access_service_token.worker.client_secret
  sensitive   = true
}
