# Remote state in Azure Storage (blob-lease locking is automatic).
# Partial config: the coordinates are supplied at init time via -backend-config
# so the same file works locally and in CI. See backend.hcl.example.
terraform {
  backend "azurerm" {
    key              = "foundation.tfstate"
    use_azuread_auth = true # authenticate to the state blob as the logged-in identity
  }
}
