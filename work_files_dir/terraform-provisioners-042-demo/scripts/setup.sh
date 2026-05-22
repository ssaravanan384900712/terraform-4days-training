#!/bin/bash
# scripts/setup.sh
# Idempotent setup script for robochef.co

set -e

echo "[setup.sh] Starting setup for robochef.co at $(date)"

# Update package lists
apt-get update -y

# Install nginx if not already present
if ! command -v nginx &>/dev/null; then
  apt-get install -y nginx
  echo "[setup.sh] nginx installed"
else
  echo "[setup.sh] nginx already present, skipping install"
fi

# Start and enable nginx
systemctl enable nginx
systemctl start nginx

echo "[setup.sh] Setup complete for robochef.co at $(date)"
