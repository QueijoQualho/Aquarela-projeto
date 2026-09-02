# resource "kubernetes_namespace" "keda" {
#   metadata {
#     name = "keda"
#   }
# }

# resource "helm_release" "keda" {
#   name       = "keda"
#   namespace  = kubernetes_namespace.keda.metadata[0].name
#   repository = "https://kedacore.github.io/charts"
#   chart      = "keda"
#   version    = "2.13.2"

#   values = [
#     <<EOF
# replicaCount: 1
# EOF
#   ]

#   depends_on = [kubernetes_namespace.keda]
# }
