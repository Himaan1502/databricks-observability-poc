terraform {
  backend "azurerm" {
    key              = "workspace.tfstate"
    use_azuread_auth = true
  }
}
