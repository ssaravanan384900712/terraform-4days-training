# main.tf

# ── SSH Key Pair ────────────────────────────────────────────────────────────

resource "tls_private_key" "demo" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "private_key" {
  filename        = "/tmp/terraform-043-demo.pem"
  content         = tls_private_key.demo.private_key_pem
  file_permission = "0600"
}

resource "aws_key_pair" "demo" {
  key_name   = "terraform-043-ansible-demo"
  public_key = tls_private_key.demo.public_key_openssh
}

# ── Security Group ──────────────────────────────────────────────────────────

resource "aws_security_group" "web" {
  name        = "terraform-043-web-sg"
  description = "Allow SSH and HTTP for Ansible integration demo"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # restrict to your IP in production
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
    Name    = "terraform-043-web-sg"
    Project = "terraform-043"
  }
}

# ── EC2 Instance ────────────────────────────────────────────────────────────

resource "aws_instance" "web" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.demo.key_name
  vpc_security_group_ids      = [aws_security_group.web.id]
  associate_public_ip_address = true

  tags = {
    Name        = "${var.app_name}-ansible-demo"
    Project     = "terraform-043"
    ManagedBy   = "terraform+ansible"
    Application = var.app_name
  }
}

# ── Ansible Provisioner ─────────────────────────────────────────────────────
#
# This null_resource fires after the EC2 instance is created.
# It calls ansible-playbook on the local machine via local-exec.
# The instance IP is passed as an inline inventory (-i '<ip>,').
# The trailing comma after the IP tells Ansible this is an inline
# inventory string, not a file path.

resource "null_resource" "ansible_provision" {
  depends_on = [aws_instance.web, local_sensitive_file.private_key]

  # Re-run Ansible if the instance is replaced OR the playbook changes
  triggers = {
    instance_id   = aws_instance.web.id
    playbook_hash = filemd5("${path.module}/playbooks/install_nginx.yml")
  }

  provisioner "local-exec" {
    command = <<-EOC
      echo "Waiting 30 seconds for SSH to become available on ${aws_instance.web.public_ip}..."
      sleep 30

      echo "Running Ansible playbook against ${aws_instance.web.public_ip}..."
      ANSIBLE_HOST_KEY_CHECKING=False \
      ANSIBLE_SSH_RETRIES=3 \
      ansible-playbook \
        -i '${aws_instance.web.public_ip},' \
        -u ubuntu \
        --private-key ${local_sensitive_file.private_key.filename} \
        --extra-vars "app_name=${var.app_name} app_domain=${var.app_domain}" \
        playbooks/install_nginx.yml

      echo "Ansible provisioning complete."
    EOC
  }
}
