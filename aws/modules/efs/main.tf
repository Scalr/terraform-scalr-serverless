resource "aws_efs_file_system" "cache" {
  creation_token = "${var.name}-cache"
  
  performance_mode = "generalPurpose"
  throughput_mode  = "provisioned"
  provisioned_throughput_in_mibps = var.provisioned_throughput

  tags = {
    Name = "${var.name}-cache"
  }
}

resource "aws_efs_mount_target" "cache" {
  count          = length(var.subnet_ids)
  file_system_id = aws_efs_file_system.cache.id
  subnet_id      = var.subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}

resource "aws_security_group" "efs" {
  name        = "${var.name}-efs-sg"
  description = "Security group for EFS"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-efs-sg"
  }
}

resource "aws_efs_access_point" "terraform_cache" {
  file_system_id = aws_efs_file_system.cache.id
  
  root_directory {
    path = "/terraform-cache"
    
    creation_info {
      owner_gid   = 0
      owner_uid   = 0
      permissions = "755"
    }
  }
  
  posix_user {
    gid = 0
    uid = 0
  }

  tags = {
    Name = "${var.name}-terraform-cache"
  }
}

resource "aws_efs_access_point" "providers_cache" {
  file_system_id = aws_efs_file_system.cache.id
  
  root_directory {
    path = "/providers-cache"
    
    creation_info {
      owner_gid   = 0
      owner_uid   = 0
      permissions = "755"
    }
  }
  
  posix_user {
    gid = 0
    uid = 0
  }

  tags = {
    Name = "${var.name}-providers-cache"
  }
} 