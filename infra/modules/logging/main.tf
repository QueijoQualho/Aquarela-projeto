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
        memory: 750Mi
      limits:
        cpu: 1000m
        memory: 1Gi

    esJavaOpts: "-Xms384m -Xmx384m"

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

data "kubernetes_secret" "es_credentials" {
  metadata {
    name      = "elasticsearch-master-credentials"
    namespace = kubernetes_namespace.logging.metadata[0].name
  }
  depends_on = [helm_release.elasticsearch]
}

resource "null_resource" "install_apm_integration" {
  depends_on = [helm_release.kibana, helm_release.apm_server]

  triggers = {
    kibana_release = helm_release.kibana.id
    apm_release    = helm_release.apm_server.id
  }

  provisioner "local-exec" {
    environment = {
      ES_PASS = data.kubernetes_secret.es_credentials.data["password"]
    }
    command = <<-EOT
      kubectl run apm-integration-install --rm -i --image=curlimages/curl -n logging --restart=Never -- \
        curl -s -X POST "http://kibana-kibana:5601/api/fleet/epm/packages/apm/8.5.1" \
        -H "kbn-xsrf: true" \
        -H "Content-Type: application/json" \
        -u "elastic:$ES_PASS" \
        -d '{"force": true}'
    EOT
  }

}

resource "helm_release" "apm_server" {
  name       = "apm-server"
  repository = "https://helm.elastic.co"
  chart      = "apm-server"
  namespace  = kubernetes_namespace.logging.metadata[0].name
  version    = "8.5.1"

  values = [
    <<-EOF
    imageTag: "8.5.1"

    replicas: 1

    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 500m
        memory: 512Mi

    extraEnvs:
      - name: ES_PASSWORD
        valueFrom:
          secretKeyRef:
            name: elasticsearch-master-credentials
            key: password

    apmConfig:
      apm-server.yml: |
        apm-server:
          host: "0.0.0.0:8200"

        output.elasticsearch:
          hosts:
            - "https://elasticsearch-master:9200"
          username: "elastic"
          password: "$${ES_PASSWORD}"
          ssl:
            verification_mode: "none"
    EOF
  ]

  depends_on = [
    helm_release.elasticsearch,
    helm_release.kibana
  ]
}
