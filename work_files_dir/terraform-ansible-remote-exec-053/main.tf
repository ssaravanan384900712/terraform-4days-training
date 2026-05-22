# main.tf

# ─── SSH key pair ───────────────────────────────────────────────────────────

resource "tls_private_key" "demo" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "demo" {
  key_name   = "${var.project_name}-key-053"
  public_key = tls_private_key.demo.public_key_openssh

  tags = {
    Name    = "${var.project_name}-key-053"
    Owner   = "saravanans"
    Project = "robochef.co"
  }
}

# Save private key locally so you can SSH manually
resource "local_file" "private_key" {
  content         = tls_private_key.demo.private_key_openssh
  filename        = "${path.module}/robochef_demo.pem"
  file_permission = "0600"
}

# ─── Networking ─────────────────────────────────────────────────────────────

data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "web" {
  name        = "${var.project_name}-sg-053"
  description = "Allow SSH and HTTP"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
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
    Name    = "${var.project_name}-sg-053"
    Owner   = "saravanans"
    Project = "robochef.co"
  }
}

# ─── AMI lookup ─────────────────────────────────────────────────────────────

data "aws_ami" "ubuntu_22" {
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

# ─── EC2 instance ────────────────────────────────────────────────────────────

resource "aws_instance" "web" {
  ami                         = data.aws_ami.ubuntu_22.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.demo.key_name
  vpc_security_group_ids      = [aws_security_group.web.id]
  associate_public_ip_address = true

  tags = {
    Name    = "${var.project_name}-web-053"
    Owner   = "saravanans"
    Project = "robochef.co"
  }
}

# ─── Remote provisioning via null_resource ───────────────────────────────────
#
# We use null_resource so that the provisioner lifecycle is independent of the
# EC2 resource. Destroying and re-creating null_resource re-runs the script
# without terminating the EC2 instance — useful during development.

resource "null_resource" "deploy_stack" {
  # Re-run if the instance is replaced or the script changes
  triggers = {
    instance_id = aws_instance.web.id
    script_hash = filemd5("${path.module}/scripts/robochef_stack.sh")
  }

  connection {
    type        = "ssh"
    host        = aws_instance.web.public_ip
    user        = "ubuntu"
    private_key = tls_private_key.demo.private_key_openssh
    timeout     = "5m"
  }

  # Step 1: copy the script to the remote machine
  provisioner "file" {
    source      = "${path.module}/scripts/robochef_stack.sh"
    destination = "/tmp/robochef_stack.sh"
  }

  # Step 2: make it executable and run it as root
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/robochef_stack.sh",
      "sudo /tmp/robochef_stack.sh",
    ]

    # on_failure = fail   # This is the default. Uncomment to make explicit.
    # on_failure = continue  # Use only for optional/advisory steps.
  }

  depends_on = [aws_instance.web]
}
