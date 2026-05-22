#!/bin/bash
set -e

echo "=== robochef_stack.sh starting ==="

apt-get update -y
apt-get install -y nginx ansible

systemctl start nginx
systemctl enable nginx

echo "Hello from robochef.co — deployed by Ansible+Terraform remote-exec" \
  > /var/www/html/index.html

echo "=== robochef_stack.sh complete ==="
