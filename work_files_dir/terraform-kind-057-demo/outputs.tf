output "namespace" {
  value = kubernetes_namespace.app.metadata[0].name
}

output "deployment_name" {
  value = kubernetes_deployment.app.metadata[0].name
}

output "service_name" {
  value = kubernetes_service.app.metadata[0].name
}

output "replicas" {
  value = kubernetes_deployment.app.spec[0].replicas
}

output "kubectl_commands" {
  value = <<-EOT
    # Verify resources
    kubectl get namespace ${var.app_name} --context ${var.cluster_context}
    kubectl get pods -n ${var.app_name} --context ${var.cluster_context}
    kubectl get deployment -n ${var.app_name} --context ${var.cluster_context}
    kubectl get service -n ${var.app_name} --context ${var.cluster_context}
    kubectl get configmap -n ${var.app_name} --context ${var.cluster_context}

    # Describe deployment
    kubectl describe deployment ${kubernetes_deployment.app.metadata[0].name} -n ${var.app_name} --context ${var.cluster_context}

    # Port-forward to test locally
    kubectl port-forward svc/${kubernetes_service.app.metadata[0].name} 8080:80 -n ${var.app_name} --context ${var.cluster_context}
    # Then: curl http://localhost:8080
  EOT
}
