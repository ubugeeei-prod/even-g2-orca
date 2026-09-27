# Mac initiates the outbound connection; it needs no public IP or inbound port.
resource "cloudflare_zero_trust_tunnel_cloudflared" "orca" {
  account_id = var.account_id
  name       = var.resource_name
  config_src = "cloudflare"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "orca" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.orca.id
  config = {
    ingress = [
      { hostname = var.bridge_hostname, service = var.bridge_service },
      { service = "http_status:404" }
    ]
  }
}

resource "cloudflare_dns_record" "bridge" {
  zone_id = var.zone_id
  name    = var.bridge_hostname
  content = "${cloudflare_zero_trust_tunnel_cloudflared.orca.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
}

# Only the Worker holds this service credential. The phone separately authenticates
# to the bridge with its user pairing token; neither credential replaces the other.
resource "cloudflare_zero_trust_access_service_token" "worker" {
  account_id = var.account_id
  name       = "${var.resource_name}-worker"
  duration   = var.service_token_duration
}

resource "cloudflare_zero_trust_access_policy" "worker" {
  account_id = var.account_id
  name       = "${var.resource_name}-service-only"
  decision   = "non_identity"
  include    = [{ service_token = { token_id = cloudflare_zero_trust_access_service_token.worker.id } }]
}

resource "cloudflare_zero_trust_access_application" "bridge" {
  account_id = var.account_id
  name       = "${var.resource_name}-bridge"
  domain     = var.bridge_hostname
  type       = "self_hosted"
  policies   = [{ id = cloudflare_zero_trust_access_policy.worker.id, precedence = 1 }]
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "orca" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.orca.id
}
