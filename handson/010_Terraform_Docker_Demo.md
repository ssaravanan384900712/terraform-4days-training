# Terraform Docker Demo - Training Notes

**By:** Saravanan Sundaramoorthy
**Environment:** Ubuntu Linux (GCE VM)
**Time:** ~20 minutes

## Overview

This training session demonstrates:

- Installing Docker on Ubuntu
- Running Docker containers manually
- Managing Docker images and containers
- Creating Docker resources using Terraform
- Applying and destroying infrastructure with Terraform

---

# 1. Install Docker

## Command

```
curl -sSL https://get.docker.com/ | sh
```

## Purpose

Installs Docker Engine Community Edition automatically on Ubuntu.

## Verification

```
docker version
```

## Important Notes

- Docker client and server versions were successfully installed.
- Docker daemon was running successfully.
- User received rootless mode recommendations.

---

# 2. Remove Existing Docker Containers

## Command

```
sudo docker rm -f `sudo docker ps -qa`
```

## Purpose

- Removes all running and stopped containers forcefully.

## Verification

```
sudo docker ps
```

Expected Output:

```
CONTAINER ID   IMAGE     COMMAND   CREATED   STATUS    PORTS     NAMES
```

---

# 3. View Existing Docker Images

## Command

```
sudo docker images
```

## Existing Images

- bitnami/consul
- ubuntu:22.04
- redis
- httpd

---

# 4. Pull Docker Images

## Pull Ubuntu Image

```
sudo docker pull ubuntu:22.04
```

## Pull Redis Image

```
sudo docker pull redis
```

## Pull Apache HTTPD Image

```
sudo docker pull httpd
```

## Purpose

Downloads Docker images from Docker Hub into the local system.

---

# 5. Run Docker Containers

## Run HTTPD Container

```
sudo docker run -d httpd
```

## Purpose

- Runs Apache HTTP Server in detached mode.

---

# 6. Run Container with Port Mapping

## Command

```
sudo docker run -p 8080:80 -d httpd
```

## Explanation

|Host Port|Container Port|
|---|---|
|8080|80|

- External machine accesses port 8080
- Inside container Apache runs on port 80

---

# 7. Test Application

## Command

```
curl localhost:8080
```

## Expected Output

```
<html><body><h1>It works!</h1></body></html>
```

## Purpose

Verifies container accessibility through mapped port.

---

# 8. List Running Containers

## Command

```
sudo docker ps
```

## Purpose

Displays active running containers.

---

# 9. Stop and Remove Containers

## Command

```
sudo docker rm -f `sudo docker ps -qa`
```

## Test Connectivity Again

```
curl localhost:8080
```

## Expected Output

```
curl: (7) Failed to connect to localhost port 8080
```

## Purpose

Confirms service becomes unavailable after container removal.

---

# 10. Create Terraform Docker Project

## Create Directory

```
mkdir tf_docker_democd tf_docker_demo
```

---

# 11. Create Terraform Configuration

## File: `main.tf`

```

terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.0.2"
    }
  }
}

provider "docker" {

}

resource "docker_image" "nginx" {
  name = "nginx"
}
```

---

# 12. Initialize Terraform

## Command

```
terraform init
```

## Purpose

- Downloads required provider plugins
- Creates `.terraform.lock.hcl`
- Initializes Terraform working directory

---

# 13. Terraform Apply Permission Error

## Command

```
terraform apply --auto-approve
```

## Error

```
permission denied while trying to connect to the Docker daemon socket
```

## Cause

Current user lacks permission to access Docker socket.

---

# 14. Run Terraform with Sudo

## Command

```
sudo terraform apply --auto-approve
```

## Result

Terraform successfully:

- Pulled nginx image
- Created Terraform state

---

# 15. Verify Docker Images

## Command

```
sudo docker images
```

## Observation

Nginx image now exists locally.

---

# 16. Destroy Terraform Resources

## Command

```
sudo terraform destroy --auto-approve
```

## Purpose

Removes infrastructure managed by Terraform.

---

# 17. Enhanced Terraform Configuration

## Updated `main.tf`

```


terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.0.2"
    }
  }
}

provider "docker" {

}

resource "docker_image" "nginx" {
  name = "nginx"
}

resource "docker_image" "httpd" {
  name = "httpd"
}

resource "docker_container" "http" {
  name = "myhttpdapp"
  image = docker_image.httpd.image_id
  ports {
      internal = "80"
      external = "9099"
   }
}
```

---

# 18. Terraform Apply with Container Resource

## Command

```
sudo terraform apply --auto-approve
```

## Resources Created

- nginx image
- httpd image
- Apache container

---

# 19. Verify Running Container

## Command

```
sudo docker ps
```

## Output Highlights

```
0.0.0.0:9099->80/tcp
```

## Meaning

- Host port 9099 mapped to container port 80.

---

# 20. Destroy Infrastructure Again

## Command

```
sudo terraform destroy --auto-approve
```

## Terraform Destroyed

- docker_container.http
- docker_image.httpd
- docker_image.nginx

---

# 21. Re-Apply Infrastructure

## Command

```
sudo terraform apply --auto-approve
```

## Result

Terraform recreated:

- Docker images
- HTTPD container

---

# Key Terraform Concepts Learned

|Concept|Description|
|---|---|
|Provider|Plugin used to interact with APIs|
|Resource|Infrastructure object managed by Terraform|
|terraform init|Initializes working directory|
|terraform apply|Creates infrastructure|
|terraform destroy|Removes infrastructure|
|terraform.tfstate|Stores infrastructure state|

---

# Key Docker Concepts Learned

|Concept|Description|
|---|---|
|Image|Read-only template|
|Container|Running instance of image|
|Port Mapping|Connect host port to container port|
|docker pull|Download image|
|docker run|Start container|
|docker ps|List running containers|
|docker rm -f|Remove containers forcefully|

---

# Files Generated

|File|Purpose|
|---|---|
|main.tf|Terraform configuration|
|terraform.tfstate|Terraform state tracking|
|terraform.tfstate.backup|State backup|
|.terraform.lock.hcl|Provider version lock|

---

# Best Practices

## Avoid Running Terraform with sudo

Instead add user to docker group:

```
sudo usermod -aG docker $USERnewgrp docker
```

## Use Version Control

Commit:

- `main.tf`
- `.terraform.lock.hcl`

Do not commit:

- `terraform.tfstate`
- `terraform.tfstate.backup`

---

# Summary

This session covered:

- Docker installation and container management
- Pulling and running images
- Port mapping
- Terraform Docker provider usage
- Creating Docker images and containers through Terraform
- Infrastructure lifecycle management using Terraform