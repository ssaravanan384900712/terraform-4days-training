output "namespace" {
  description = "Kubernetes namespace created"
  value       = kubernetes_namespace.app.metadata[0].name
}

output "deployment_name" {
  description = "Kubernetes deployment name"
  value       = kubernetes_deployment.app.metadata[0].name
}

output "service_name" {
  description = "Kubernetes service name"
  value       = kubernetes_service.app.metadata[0].name
}

output "verify_commands" {
  description = "Commands to verify the deployment"
  value = <<-EOT
    kubectl get namespace ${kubernetes_namespace.app.metadata[0].name}
    kubectl get pods -n ${kubernetes_namespace.app.metadata[0].name}
    kubectl get deployment -n ${kubernetes_namespace.app.metadata[0].name}
    kubectl get service -n ${kubernetes_namespace.app.metadata[0].name}
    kubectl describe deployment ${kubernetes_deployment.app.metadata[0].name} -n ${kubernetes_namespace.app.metadata[0].name}
  EOT
}
