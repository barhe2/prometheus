provider "aws" {
  region = var.region
}

data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] # Canonical
}

resource "aws_security_group" "default" {
  vpc_id      = "vpc-0965807a75a0a2d42" # Replace with your actual VPC ID
  name_prefix = "${var.cluster_name}-sg-" # Use a prefix to avoid naming conflicts
  ingress     = []
  egress      = []

  tags = {
    Name = "${var.cluster_name}-sg"
  }
}

resource "aws_instance" "control_plane" {
  count         = var.control_plane_count
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.control_plane_instance_type
  key_name      = var.key_name
  vpc_security_group_ids = ["sg-02b3d29bdcd49a0cc"]

  tags = {
    Name = "${var.cluster_name}-control-plane"
    Role = "control-plane"
    group = "dms"
  }

  root_block_device {
    volume_size = 15
  }
}

resource "aws_instance" "workers" {
  count         = var.worker_count
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.worker_instance_type
  key_name      = var.key_name
  vpc_security_group_ids = ["sg-02b3d29bdcd49a0cc"]

  tags = {
    Name = "${var.cluster_name}-worker-${count.index + 1}"
    Role = "worker"
    group = "dms"
  }

  root_block_device {
    volume_size = 15
  }
}