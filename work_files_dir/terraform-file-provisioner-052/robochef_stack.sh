#!/usr/bin/env bash
# robochef_stack.sh
# Installed by Terraform file provisioner + remote-exec
# Lab 052 — robochef.co

set -euo pipefail

echo "=== robochef.co stack setup starting ==="

# Update package list and install nginx
apt-get update -y
apt-get install -y nginx

# Enable and start nginx
systemctl enable nginx
systemctl start nginx

# Write a custom landing page
cat > /var/www/html/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <title>robochef.co</title>
</head>
<body>
  <h1>Hello from robochef.co deployed by Terraform file provisioner</h1>
  <p>This page was created by robochef_stack.sh, which was copied to
     /tmp/robochef_stack.sh using the Terraform <code>file</code>
     provisioner and then executed with <code>remote-exec</code>.</p>
</body>
</html>
HTMLEOF

echo "=== robochef.co stack setup complete ==="
