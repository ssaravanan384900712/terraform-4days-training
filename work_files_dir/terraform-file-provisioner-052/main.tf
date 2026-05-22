# ─────────────────────────────────────────────────────────────
# DATA SOURCES — AMI, VPC, Subnets
# ─────────────────────────────────────────────────────────────

# Ubuntu 22.04 LTS (Jammy) — official Canonical AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]   # Canonical's AWS account

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Use the default VPC — no custom networking required for this lab
data "aws_vpc" "default" {
  default = true
}

# Pull all subnets in the default VPC
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ─────────────────────────────────────────────────────────────
# TLS PRIVATE KEY — ED25519, Terraform-managed
# ─────────────────────────────────────────────────────────────

# Generate a fresh ED25519 key pair every time.
# The public key goes into AWS as a Key Pair.
# The private key is stored in Terraform state (sensitive) and
# also written to disk so the file provisioner connection can use it.
resource "tls_private_key" "demo" {
  algorithm = "ED25519"
}

# Save the private key to disk so we can SSH manually if needed.
# file_permission = "0600" prevents "permissions too open" SSH errors.
resource "local_file" "private_key" {
  content         = tls_private_key.demo.private_key_openssh
  filename        = "${path.module}/robochef-fp-052.pem"
  file_permission = "0600"
}

# Register the public half with AWS
resource "aws_key_pair" "demo" {
  key_name   = "${var.project_name}-key"
  public_key = tls_private_key.demo.public_key_openssh

  tags = {
    Name    = "${var.project_name}-key"
    Owner   = var.owner
    Project = var.project_tag
  }
}

# ─────────────────────────────────────────────────────────────
# SECURITY GROUP — SSH (22) ingress, all egress
# ─────────────────────────────────────────────────────────────

resource "aws_security_group" "demo" {
  name        = "${var.project_name}-sg"
  description = "Allow SSH ingress for file-provisioner demo"
  vpc_id      = data.aws_vpc.default.id

  # SSH — needed for both file provisioner and remote-exec provisioner
  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP — to verify nginx after script runs
  ingress {
    description = "HTTP to verify nginx"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-sg"
    Owner   = var.owner
    Project = var.project_tag
  }
}

# ─────────────────────────────────────────────────────────────
# EC2 INSTANCE — with file provisioner + remote-exec provisioner
# ─────────────────────────────────────────────────────────────

resource "aws_instance" "demo" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.demo.id]
  key_name                    = aws_key_pair.demo.key_name
  associate_public_ip_address = true

  tags = {
    Name    = "${var.project_name}-ec2"
    Owner   = var.owner
    Project = var.project_tag
  }

  # ── CONNECTION BLOCK ─────────────────────────────────────────
  # Defined at the resource level so ALL provisioners inside this
  # resource share the same connection settings.
  # The private key is read directly from the tls_private_key resource —
  # no local file path needed for the connection itself.
  connection {
    type        = "ssh"
    user        = "ubuntu"             # Ubuntu 22.04 default user
    host        = self.public_ip
    private_key = tls_private_key.demo.private_key_openssh
    timeout     = "4m"
  }

  # ── PROVISIONER 1: file — copy data.txt ──────────────────────
  #
  # Teaching point:
  #   • `source`      = local path (relative to the Terraform working dir)
  #   • `destination` = absolute path on the remote server
  #   • The file provisioner ONLY copies. It does NOT run anything.
  #   • Destination must be writable by the SSH user.
  #     /tmp is always writable, so it is a safe landing zone.
  #
  provisioner "file" {
    source      = "${path.module}/data.txt"
    destination = "/tmp/data.txt"
  }

  # ── PROVISIONER 2: file — copy the setup script ──────────────
  #
  # Teaching point:
  #   • Copying a shell script does NOT execute it.
  #   • The script lands at /tmp/robochef_stack.sh with whatever
  #     permissions the SSH user can set — usually 644 by default.
  #   • We will use remote-exec next to actually run it with sudo.
  #
  provisioner "file" {
    source      = "${path.module}/robochef_stack.sh"
    destination = "/tmp/robochef_stack.sh"
  }

  # ── PROVISIONER 3: remote-exec — run the copied script ───────
  #
  # Teaching point:
  #   • `inline` runs commands in order, one per list element.
  #   • We first chmod the script to ensure it is executable,
  #     then run it with sudo (nginx install requires root).
  #   • Provisioners in the same resource run in declaration order:
  #     file (data.txt) → file (script) → remote-exec.
  #
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/robochef_stack.sh",
      "sudo bash /tmp/robochef_stack.sh",
    ]
  }

  # Ensure the TLS key is fully created before this resource attempts
  # its SSH connection.
  depends_on = [tls_private_key.demo]
}

# ─────────────────────────────────────────────────────────────
# NULL RESOURCE DEMO — file provisioner outside an EC2 resource
# ─────────────────────────────────────────────────────────────
#
# Teaching point:
#   Sometimes you want to copy a file to an already-running instance
#   without recreating it. A null_resource with a trigger on a
#   content hash lets you re-run the file provisioner whenever
#   the source file changes — without touching the EC2 resource.
#
resource "null_resource" "recopy_data" {
  # Re-run whenever data.txt changes
  triggers = {
    data_txt_hash = filemd5("${path.module}/data.txt")
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    host        = aws_instance.demo.public_ip
    private_key = tls_private_key.demo.private_key_openssh
    timeout     = "4m"
  }

  provisioner "file" {
    source      = "${path.module}/data.txt"
    destination = "/tmp/data.txt"
  }

  depends_on = [aws_instance.demo]
}
