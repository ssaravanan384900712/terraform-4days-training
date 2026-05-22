# ─────────────────────────────────────────────
# Namespace
# ─────────────────────────────────────────────

resource "kubernetes_namespace" "app" {
  metadata {
    name = var.app_name
    labels = {
      owner   = "saravanans"
      project = "robochef.co"
      env     = "kind-local"
    }
  }
}

# ─────────────────────────────────────────────
# ConfigMap
# ─────────────────────────────────────────────

resource "kubernetes_config_map" "app" {
  metadata {
    name      = "${var.app_name}-config"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  data = {
    APP_NAME    = "robochef.co"
    APP_OWNER   = "saravanans"
    APP_ENV     = "kind-local"
    APP_PORT    = "80"
  }
}

# ─────────────────────────────────────────────
# Deployment
# ─────────────────────────────────────────────

resource "kubernetes_deployment" "app" {
  metadata {
    name      = "${var.app_name}-deployment"
    namespace = kubernetes_namespace.app.metadata[0].name
    labels = {
      app     = var.app_name
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
          name  = "nginx"
          image = var.image

          port {
            container_port = 80
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map.app.metadata[0].name
            }
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "64Mi"
            }
          }
        }
      }
    }
  }
}

# ─────────────────────────────────────────────
# Service (NodePort — accessible on localhost via kind port mapping)
# ─────────────────────────────────────────────

resource "kubernetes_service" "app" {
  metadata {
    name      = "${var.app_name}-service"
    namespace = kubernetes_namespace.app.metadata[0].name
    labels = {
      app     = var.app_name
      owner   = "saravanans"
      project = "robochef.co"
    }
  }

  spec {
    selector = {
      app = var.app_name
    }

    port {
      port        = 80
      target_port = 80
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}
