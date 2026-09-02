module "aks" {
  source              = "../../modules/aks"
  resource_group_name = var.resource_group_name
  location            = var.location
  aks_cluster_name    = var.aks_cluster_name
  node_count          = var.node_count
  vm_size             = var.vm_size
}

resource "azurerm_public_ip" "ingress_ip" {
  name                = "myAKSPublicIPForIngress"
  location            = module.aks.location
  resource_group_name = module.aks.node_resource_group
  allocation_method   = "Static"
  sku                 = "Standard"

  depends_on = [module.aks]
}

module "cert_manager" {
  source     = "../../modules/cert-manager"
  depends_on = [module.aks]
}

module "ingress_nginx" {
  source              = "../../modules/ingress-nginx"
  public_ip_address   = azurerm_public_ip.ingress_ip.ip_address
  node_resource_group = module.aks.node_resource_group
  depends_on          = [module.aks, azurerm_public_ip.ingress_ip]
}

# module "keda" {
#   source     = "../../modules/keda"
#   depends_on = [module.aks]
# }

module "monitoring" {
  source     = "../../modules/monitoring"
  depends_on = [module.aks]
}

module "logging" {
  source            = "../../modules/logging"
  depends_on        = [module.aks]
}
