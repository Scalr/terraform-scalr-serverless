output "file_system_id" {
  description = "EFS file system ID"
  value       = aws_efs_file_system.cache.id
}

output "scalr_agent_cache_access_point_id" {
  description = "EFS access point ID for the agent cache"
  value       = aws_efs_access_point.scalr_agent_cache.id
}

output "security_group_id" {
  description = "Security group ID for EFS"
  value       = aws_security_group.efs.id
}
