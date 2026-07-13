# Single-node k3s "cluster" on a free-tier EC2 instance. No SSH key, no inbound
# port 22, no inbound 6443 — administrative access (kubectl, Argo CD UI) goes
# through AWS Systems Manager Session Manager instead, so nothing but the
# status-api demo port is ever exposed to the internet.

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "node" {
  name        = "${var.project}-k3s-node"
  description = "status-api demo port only; everything else via SSM Session Manager."
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "status-api demo (public)"
    from_port   = var.status_api_nodeport
    to_port     = var.status_api_nodeport
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project = var.project
  }
}

resource "aws_iam_role" "node" {
  name = "${var.project}-k3s-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "node" {
  name = "${var.project}-k3s-node"
  role = aws_iam_role.node.name
}

resource "aws_instance" "node" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.node.id]
  iam_instance_profile   = aws_iam_instance_profile.node.name

  user_data = templatefile("${path.module}/user_data.sh.tpl", {
    github_repo          = var.github_repo
    deploy_datadog_agent = var.deploy_datadog_agent
  })
  user_data_replace_on_change = true

  root_block_device {
    volume_size = 20 # free tier: 30GB, gp2/magnetic only — gp3 is billed from byte one
    volume_type = "gp2"
  }

  tags = {
    Name    = "${var.project}-k3s-node"
    Project = var.project
  }
}


# Since Feb 2024, AWS bills all public IPv4 addresses ($0.005/hr) regardless of
# attachment — the old "free while attached to a running instance" EIP exception
# no longer applies. A new account gets 750 free public-IPv4 hours/month for its
# first 12 months, which one EIP running continuously (~730-744 hrs/month) fits
# under. This doesn't change the EIP-vs-default-public-IP tradeoff either way —
# both are billed identically now — so a stable address remains the right choice.
resource "aws_eip" "node" {
  instance = aws_instance.node.id
  domain   = "vpc"

  tags = {
    Project = var.project
  }
}
