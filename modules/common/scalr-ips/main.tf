# Fetch official Scalr.io IP allowlist
# This module is separate from agent pool to avoid circular dependencies

data "http" "scalr_allowlist" {
  url = "https://scalr.io/.well-known/allowlist.txt"
}

locals {
  # Split the response by newlines and filter out empty lines
  scalr_ips = [for ip in split("\n", trimspace(data.http.scalr_allowlist.response_body)) : "${ip}/32" if ip != ""]
}
