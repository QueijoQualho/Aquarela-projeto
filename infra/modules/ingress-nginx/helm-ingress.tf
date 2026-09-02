resource "kubernetes_namespace" "ingress" {
  metadata {
    name = "ingress-nginx"
  }
}

resource "helm_release" "nginx_ingress" {
  name       = "ingress-nginx"
  namespace  = kubernetes_namespace.ingress.metadata[0].name
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.15.1"

  values = [
    <<-EOF
    controller:
      replicaCount: 2
      nodeSelector:
        kubernetes.io/os: linux
      service:
        type: LoadBalancer
        loadBalancerIP: "${var.public_ip_address}"
    defaultBackend:
      nodeSelector:
        kubernetes.io/os: linux
    EOF
  ]
}
