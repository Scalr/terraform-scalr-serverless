output "allowed_ips" {
  description = "List of official Scalr.io IP addresses with /32 CIDR notation"
  value       = local.scalr_ips
}

output "raw_ips" {
  description = "Raw list of Scalr.io IP addresses without CIDR notation"
  value       = split("\n", trimspace(data.http.scalr_allowlist.response_body))
}
