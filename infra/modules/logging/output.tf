output "elasticsearch_service" {
  value       = "elasticsearch-master"
}

output "elasticsearch_url" {
  value       = "https://elasticsearch-master.${kubernetes_namespace.logging.metadata[0].name}.svc.cluster.local:9200"
}

output "kibana_service" {
  value       = "kibana-kibana"
}

output "kibana_url" {
  value       = "https://kibana-kibana.${kubernetes_namespace.logging.metadata[0].name}.svc.cluster.local:5601"
}

output "kibana_ingress_host" {
  value       = "kibana.local"
}

output "logging_namespace" {
  value       = kubernetes_namespace.logging.metadata[0].name
}
