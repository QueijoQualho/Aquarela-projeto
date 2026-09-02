resource "kubernetes_namespace" "logging" {
  metadata {
    name = "logging"
  }
}

resource "helm_release" "fluent_bit" {
  name       = "fluent-bit"
  repository = "https://fluent.github.io/helm-charts"
  chart      = "fluent-bit"
  namespace  = kubernetes_namespace.logging.metadata[0].name
  version    = "0.48.6"

  values = [
    <<-EOF
    resources:
      requests:
        cpu: 50m
        memory: 64Mi
      limits:
        memory: 128Mi

    env:
      - name: ES_PASSWORD
        valueFrom:
          secretKeyRef:
            name: elasticsearch-master-credentials
            key: password

    config:
      outputs: |
        [OUTPUT]
            Name              es
            Match             kube.*
            Host              elasticsearch-master
            Port              9200
            TLS               On
            TLS.Verify        Off
            HTTP_User         elastic
            HTTP_Passwd       $${ES_PASSWORD}
            Index             sock-shop-logs
            Suppress_Type_Name On
            Retry_Limit       False
    EOF
  ]

  depends_on = [helm_release.elasticsearch]
}

resource "helm_release" "elasticsearch" {
  name       = "elasticsearch"
  repository = "https://helm.elastic.co"
  chart      = "elasticsearch"
  namespace  = kubernetes_namespace.logging.metadata[0].name
  version    = "8.5.1"

  values = [
    <<-EOF
    replicas: 1
    minimumMasterNodes: 1

    resources:
      requests:
        cpu: 300m
        memory: 1Gi
      limits:
        cpu: 1000m
        memory: 1.5Gi

    esJavaOpts: "-Xms512m -Xmx512m"

    persistence:
      enabled: false
    EOF
  ]
}

resource "helm_release" "kibana" {
  name       = "kibana"
  repository = "https://helm.elastic.co"
  chart      = "kibana"
  namespace  = kubernetes_namespace.logging.metadata[0].name
  version    = "8.5.1"

  values = [
    <<-EOF
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        memory: 512Mi

    elasticsearchHosts: "https://elasticsearch-master:9200"
    EOF
  ]

  depends_on = [helm_release.elasticsearch]
}

resource "kubernetes_ingress_v1" "kibana" {
  metadata {
    name      = "kibana"
    namespace = kubernetes_namespace.logging.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer" = "selfsigned-issuer"
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["kibana.local"]
      secret_name = "kibana-tls"
    }

    rule {
      host = "kibana.local"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "kibana-kibana"
              port {
                number = 5601
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.kibana]
}
