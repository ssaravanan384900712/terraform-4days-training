# main.tf

# ── Demo 1: local-exec ──────────────────────────────────────────────────────

resource "null_resource" "local_script" {
  provisioner "local-exec" {
    command = "echo 'Deployed robochef.co at $(date)' >> /tmp/deploy-log.txt"
  }

  provisioner "local-exec" {
    command     = "echo 'Checking Python version...'; python3 --version"
    interpreter = ["/bin/bash", "-c"]
  }
}

resource "null_resource" "on_destroy" {
  provisioner "local-exec" {
    when    = destroy
    command = "echo 'Cleaning up robochef.co resources...' >> /tmp/deploy-log.txt"
  }
}

# ── Demo 2 + 3 setup: SSH key + EC2 ────────────────────────────────────────

resource "tls_private_key" "demo" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "private_key" {
  filename        = "/tmp/terraform-042-demo.pem"
  content         = tls_private_key.demo.private_key_pem
  file_permission = "0600"
}

resource "aws_key_pair" "demo" {
  key_name   = "terraform-042-demo"
  public_key = tls_private_key.demo.public_key_openssh
}

resource "aws_security_group" "demo" {
  name        = "terraform-042-provisioner-sg"
  description = "Allow SSH for provisioner demo"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]   # restrict to your IP in production
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "web" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.demo.key_name
  vpc_security_group_ids      = [aws_security_group.demo.id]
  associate_public_ip_address = true

  tags = {
    Name    = "robochef-provisioner-demo"
    Project = "terraform-042"
  }
}

# ── Demo 2: file provisioner ────────────────────────────────────────────────

resource "null_resource" "file_copy" {
  depends_on = [aws_instance.web]

  # Re-run this resource if the instance is replaced
  triggers = {
    instance_id = aws_instance.web.id
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.demo.private_key_pem
    host        = aws_instance.web.public_ip
    timeout     = "2m"
  }

  provisioner "file" {
    source      = "scripts/setup.sh"
    destination = "/tmp/setup.sh"
  }
}

# ── Demo 3: remote-exec provisioner ────────────────────────────────────────

resource "null_resource" "remote_commands" {
  depends_on = [null_resource.file_copy]

  triggers = {
    instance_id = aws_instance.web.id
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.demo.private_key_pem
    host        = aws_instance.web.public_ip
    timeout     = "2m"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/setup.sh",
      "sudo /tmp/setup.sh",
      "echo 'Setup complete for robochef.co'"
    ]
  }
}
