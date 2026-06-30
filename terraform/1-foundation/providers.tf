# Auth: run `az login` first. azurerm 4.x requires the subscription id
# explicitly (here via var, or export ARM_SUBSCRIPTION_ID instead).
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
