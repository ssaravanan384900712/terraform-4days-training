# ── EKS auth data sources (used by the kubernetes provider in providers.tf) ───
data "aws_eks_cluster" "this" {
  name = aws_eks_cluster.this.name
}

data "aws_eks_cluster_auth" "this" {
  name = aws_eks_cluster.this.name
}

# ── 1. Namespace ───────────────────────────────────────────────────────────────
resource "kubernetes_namespace" "app" {
  metadata {
    name = var.app_name

    labels = {
      owner   = "saravanans"
      project = "robochef.co"
    }
  }
}

# ── 2. ConfigMap ───────────────────────────────────────────────────────────────
resource "kubernetes_config_map" "app" {
  metadata {
    name      = "${var.app_name}-config"
    namespace = kubernetes_namespace.app.metadata[0].name

    labels = {
      owner   = "saravanans"
      project = "robochef.co"
    }
  }

  data = {
    APP_ENV     = "production"
    APP_OWNER   = "saravanans"
    APP_PROJECT = "robochef.co"
    APP_PORT    = "80"
  }
}

# ── 3. Deployment ──────────────────────────────────────────────────────────────
resource "kubernetes_deployment" "app" {
  metadata {
    name      = "${var.app_name}-deployment"
    namespace = kubernetes_namespace.app.metadata[0].name

    labels = {
      owner   = "saravanans"
      project = "robochef.co"
    }
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = {
        app = var.app_name
      }
    }

    template {
      metadata {
        labels = {
          app     = var.app_name
          owner   = "saravanans"
          project = "robochef.co"
        }
      }

      spec {
        container {
          name  = var.app_name
          image = "nginx:alpine"

          port {
            container_port = 80
          }

          # Inject every key from the ConfigMap as an environment variable
          env_from {
            config_map_ref {
              name = kubernetes_config_map.app.metadata[0].name
            }
          }

          # Resource requests tell the scheduler the minimum headroom needed.
          # Limits cap how much the container can consume.
          # Both are important on small nodes like t3.small (2 vCPU, 2 GB RAM).
          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
        }
      }
    }
  }
}

# ── 4. Service ─────────────────────────────────────────────────────────────────
resource "kubernetes_service" "app" {
  metadata {
    name      = "${var.app_name}-service"
    namespace = kubernetes_namespace.app.metadata[0].name

    labels = {
      owner   = "saravanans"
      project = "robochef.co"
    }
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = var.app_name
    }

    port {
      port        = 80
      target_port = 80
      protocol    = "TCP"
    }
  }
}
