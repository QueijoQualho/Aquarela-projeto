data "terraform_remote_state" "aks" {
  backend = "azurerm"
  config = {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "sttfstateprod"
    container_name        = "tfstate"
    key                    = "dev/01-aks.tfstate"
  }
}

data "azurerm_kubernetes_cluster" "aks_data" {
  name                = data.terraform_remote_state.aks.outputs.cluster_name
  resource_group_name = data.terraform_remote_state.aks.outputs.resource_group_name
}
