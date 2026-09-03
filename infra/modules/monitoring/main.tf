resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

resource "helm_release" "kube_prometheus_stack" {
  name       = "monitoring"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  version    = "65.5.1"

  values = [
    <<-EOF
    grafana:
      service:
        type: ClusterIP
      adminPassword: "admin123"

    prometheus:
      prometheusSpec:
        resources:
          requests:
            cpu: 200m
            memory: 512Mi
          limits:
            memory: 1Gi
        retention: 3d
    EOF
  ]
}

resource "kubernetes_ingress_v1" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer" = "selfsigned-issuer"
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["grafana.local"]
      secret_name = "grafana-tls"
    }

    rule {
      host = "grafana.local"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "monitoring-grafana"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.kube_prometheus_stack]
}

resource "kubectl_manifest" "sock_shop_alert" {
  yaml_body = <<-YAML
    apiVersion: monitoring.coreos.com/v1
    kind: PrometheusRule
    metadata:
      name: sock-shop-alerts
      namespace: monitoring
      labels:
        release: monitoring
    spec:
      groups:
        - name: sock-shop.rules
          rules:
            - alert: FrontEndDown
              expr: kube_deployment_status_replicas_available{namespace="sock-shop", deployment="front-end"} == 0
              for: 2m
              labels:
                severity: critical
              annotations:
                summary: "Front-end está fora do ar"
                description: "O deployment front-end está com 0 réplicas disponíveis há mais de 2 minutos."
  YAML

  depends_on = [helm_release.kube_prometheus_stack]
}
