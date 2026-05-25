output "file_system_id" {
  description = "EFS file system ID"
  value       = aws_efs_file_system.cache.id
}

output "terraform_cache_access_point_id" {
  description = "EFS access point ID for Terraform cache"
  value       = aws_efs_access_point.terraform_cache.id
}

output "providers_cache_access_point_id" {
  description = "EFS access point ID for providers cache"
  value       = aws_efs_access_point.providers_cache.id
}

output "security_group_id" {
  description = "Security group ID for EFS"
  value       = aws_security_group.efs.id
} 