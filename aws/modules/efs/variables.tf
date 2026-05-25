variable "name" {
  description = "Name prefix for EFS resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where EFS will be created"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block for security group rules"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for EFS mount targets"
  type        = list(string)
}

variable "provisioned_throughput" {
  description = "Provisioned throughput for EFS in MiB/s"
  type        = number
  default     = 100
} 