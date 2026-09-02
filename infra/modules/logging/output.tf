output "elasticsearch_service" {
  description = "Nome do Service do Elasticsearch"
  value       = "elasticsearch-master"
}

output "elasticsearch_url" {
  description = "URL interna do Elasticsearch"
  value       = "https://elasticsearch-master.${kubernetes_namespace.logging.metadata[0].name}.svc.cluster.local:9200"
}

output "kibana_service" {
  description = "Nome do Service do Kibana"
  value       = "kibana-kibana"
}

output "kibana_url" {
  description = "URL interna do Kibana"
  value       = "https://kibana-kibana.${kubernetes_namespace.logging.metadata[0].name}.svc.cluster.local:5601"
}

output "kibana_ingress_host" {
  description = "Host configurado para acessar o Kibana pelo Ingress"
  value       = "kibana.local"
}

output "logging_namespace" {
  description = "Namespace onde estão Elasticsearch, Kibana e Fluent Bit"
  value       = kubernetes_namespace.logging.metadata[0].name
}
