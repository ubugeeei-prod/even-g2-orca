# A mock plan validates topology without an account, secrets, or deployed resources.
mock_provider "cloudflare" {}

run "only_worker_can_access_loopback_bridge" {
  command = plan
  variables {
    account_id      = "00000000000000000000000000000000"
    zone_id         = "00000000000000000000000000000000"
    bridge_hostname = "orca-bridge.example.com"
  }
  assert {
    condition     = cloudflare_zero_trust_access_policy.worker.decision == "non_identity"
    error_message = "The bridge must require a service token."
  }
  assert {
    condition     = cloudflare_zero_trust_tunnel_cloudflared_config.orca.config.ingress[0].service == "http://127.0.0.1:3210"
    error_message = "The tunnel must forward to the loopback bridge."
  }
  assert {
    condition     = cloudflare_zero_trust_tunnel_cloudflared_config.orca.config.ingress[1].service == "http_status:404"
    error_message = "Unmatched tunnel routes must be rejected."
  }
}
