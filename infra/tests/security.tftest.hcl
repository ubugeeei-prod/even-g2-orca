# A mock plan checks the topology without an account, credentials or resources.
mock_provider "cloudflare" {}

variables {
  account_id      = "00000000000000000000000000000000"
  zone_id         = "00000000000000000000000000000000"
  app_hostname    = "orca.example.com"
  bridge_hostname = "orca-bridge.example.com"
  dist_dir        = "tests/fixtures/build"
}

run "bridge_is_reachable_only_through_the_worker" {
  command = plan

  assert {
    condition     = cloudflare_zero_trust_access_policy.worker.decision == "non_identity"
    error_message = "The bridge hostname must require the Worker's service token."
  }
  assert {
    condition     = cloudflare_zero_trust_tunnel_cloudflared_config.bridge.config.ingress[0].service == "http://127.0.0.1:3210"
    error_message = "The tunnel must forward to the loopback bridge."
  }
  assert {
    condition     = cloudflare_zero_trust_tunnel_cloudflared_config.bridge.config.ingress[1].service == "http_status:404"
    error_message = "Unmatched tunnel routes must be rejected."
  }
}

run "worker_keeps_access_credentials_secret" {
  command = plan

  assert {
    condition = length([
      for b in cloudflare_workers_script.app.bindings : b
      if contains(["ACCESS_CLIENT_ID", "ACCESS_CLIENT_SECRET"], b.name) && b.type == "secret_text"
    ]) == 2
    error_message = "Access credentials must be secret bindings."
  }
  assert {
    condition = one([
      for b in cloudflare_workers_script.app.bindings : b.text if b.name == "BRIDGE_ORIGIN"
    ]) == "https://orca-bridge.example.com"
    error_message = "The Worker must relay only to the tunnel hostname."
  }
}

run "wildcard_origins_are_rejected" {
  command = plan

  variables {
    allowed_origins = "*"
  }

  expect_failures = [var.allowed_origins]
}
