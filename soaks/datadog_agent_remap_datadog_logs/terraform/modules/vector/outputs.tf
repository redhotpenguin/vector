output "namespace" {
  description = "The namespace this vector experiment runs in"
  value = kubernetes_namespace.vector.metadata[0].name
}

output "type" {
  description = "The type of the vector install, whether 'baseline' or 'comparision'"
  value = var.type
}
