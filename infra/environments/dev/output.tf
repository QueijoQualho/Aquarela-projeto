output "aks-login" {
  value = "az aks get-credentials --resource-group ${var.resource_group_name} --name ${var.aks_cluster_name}"
}

output "nginx_ip" {
  value = azurerm_public_ip.ingress_ip.ip_address
}

output "sock_shop_url" {
  value = "http://${azurerm_public_ip.ingress_ip.ip_address}"
}
