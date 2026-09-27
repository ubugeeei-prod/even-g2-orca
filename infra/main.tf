locals {
  dist        = var.dist_dir != "" ? var.dist_dir : "${path.module}/../dist"
  worker_file = "${local.dist}/worker/worker.js"
}

# --- Mac bridge behind a Tunnel ------------------------------------------------
# The Mac dials out; it needs no public IP or inbound port.

resource "cloudflare_zero_trust_tunnel_cloudflared" "bridge" {
  account_id = var.account_id
  name       = var.resource_name
  config_src = "cloudflare"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "bridge" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.bridge.id
  config = {
    ingress = [
      { hostname = var.bridge_hostname, service = var.bridge_service },
      { service = "http_status:404" },
    ]
  }
}

resource "cloudflare_dns_record" "bridge" {
  zone_id = var.zone_id
  name    = var.bridge_hostname
  content = "${cloudflare_zero_trust_tunnel_cloudflared.bridge.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "bridge" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.bridge.id
}

# --- Access: only the Worker may reach the bridge hostname ----------------------
# The phone never sees this credential; it separately presents the bridge's
# pairing token, which the bridge verifies itself.

resource "cloudflare_zero_trust_access_service_token" "worker" {
  account_id = var.account_id
  name       = "${var.resource_name}-worker"
  duration   = var.service_token_duration
}

resource "cloudflare_zero_trust_access_policy" "worker" {
  account_id = var.account_id
  name       = "${var.resource_name}-worker-only"
  decision   = "non_identity"
  include = [
    { service_token = { token_id = cloudflare_zero_trust_access_service_token.worker.id } },
  ]
}

resource "cloudflare_zero_trust_access_application" "bridge" {
  account_id = var.account_id
  name       = "${var.resource_name}-bridge"
  domain     = var.bridge_hostname
  type       = "self_hosted"
  policies = [
    { id = cloudflare_zero_trust_access_policy.worker.id, precedence = 1 },
  ]
}

# --- Worker: phone app assets and the API relay ---------------------------------

resource "cloudflare_workers_script" "app" {
  account_id         = var.account_id
  script_name        = var.resource_name
  main_module        = "worker.js"
  content_file       = local.worker_file
  content_sha256     = filesha256(local.worker_file)
  compatibility_date = var.compatibility_date

  assets = {
    directory = "${local.dist}/web"
  }

  bindings = [
    { name = "ASSETS", type = "assets" },
    { name = "BRIDGE_ORIGIN", type = "plain_text", text = "https://${var.bridge_hostname}" },
    { name = "ALLOWED_ORIGINS", type = "plain_text", text = var.allowed_origins },
    { name = "ACCESS_CLIENT_ID", type = "secret_text", text = cloudflare_zero_trust_access_service_token.worker.client_id },
    { name = "ACCESS_CLIENT_SECRET", type = "secret_text", text = cloudflare_zero_trust_access_service_token.worker.client_secret },
  ]
}

resource "cloudflare_workers_custom_domain" "app" {
  account_id  = var.account_id
  zone_id     = var.zone_id
  hostname    = var.app_hostname
  service     = cloudflare_workers_script.app.script_name
  environment = "production"
}
