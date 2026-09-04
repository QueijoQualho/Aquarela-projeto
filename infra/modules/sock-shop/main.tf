locals {
  manifests_path = "${path.module}/../../../manifests"

  all_manifests = concat(
    tolist(fileset(local.manifests_path, "*.yaml")),
    tolist(fileset(local.manifests_path, "*.yml"))
  )

  app_manifests = [
    for f in local.all_manifests : f
    if f != "00-sock-shop-ns.yaml"
  ]
}

resource "kubectl_manifest" "namespace" {
  yaml_body = file("${local.manifests_path}/00-sock-shop-ns.yaml")
}

resource "kubectl_manifest" "sock_shop" {
  for_each = toset(local.app_manifests)

  yaml_body = file("${local.manifests_path}/${each.value}")

  depends_on = [
    kubectl_manifest.namespace
  ]
}
