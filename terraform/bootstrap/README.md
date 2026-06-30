# One-time bootstrap (run locally, once)

Two things must exist before the pipeline can run: a **storage account for
Terraform state**, and a **GitHub OIDC identity** so Actions can authenticate to
Azure without stored secrets. Both are chicken-and-egg with the pipeline, so
create them by hand once.

Prereqs: `az login`, and the GitHub CLI `gh` (or set the repo vars in the UI).

```bash
# ---- Pick names (must be globally unique for the storage account) ----
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
LOCATION="centralindia"
STATE_RG="rg-tfstate"
STATE_SA="sttfstatedbxobs$RANDOM"     # 3-24 lowercase alphanumerics, globally unique
STATE_CONTAINER="tfstate"
REPO="your-org/your-repo"             # GitHub owner/repo

# ---- 1) State storage account + container ----
az group create -n "$STATE_RG" -l "$LOCATION"
az storage account create -n "$STATE_SA" -g "$STATE_RG" -l "$LOCATION" \
  --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 \
  --allow-blob-public-access false
az storage container create --account-name "$STATE_SA" -n "$STATE_CONTAINER" \
  --auth-mode login

# ---- 2) Azure AD app + service principal for GitHub OIDC ----
APP_ID=$(az ad app create --display-name "gh-oidc-dbx-obs" --query appId -o tsv)
az ad sp create --id "$APP_ID"
SP_OBJECT_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv)

# Federated credentials: one for PR plans, one for the gated 'azure-poc' env apply
az ad app federated-credential create --id "$APP_ID" --parameters "{
  \"name\":\"gh-pr\",
  \"issuer\":\"https://token.actions.githubusercontent.com\",
  \"subject\":\"repo:${REPO}:pull_request\",
  \"audiences\":[\"api://AzureADTokenExchange\"]
}"
az ad app federated-credential create --id "$APP_ID" --parameters "{
  \"name\":\"gh-env-azure-poc\",
  \"issuer\":\"https://token.actions.githubusercontent.com\",
  \"subject\":\"repo:${REPO}:environment:azure-poc\",
  \"audiences\":[\"api://AzureADTokenExchange\"]
}"

# ---- 3) Role assignments for the SP ----
# Contributor on the subscription (POC scope) – tighten to an RG for real use.
az role assignment create --assignee "$APP_ID" --role "Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"
# Read/write the state blobs as this identity.
az role assignment create --assignee "$APP_ID" --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$STATE_RG/providers/Microsoft.Storage/storageAccounts/$STATE_SA"

TENANT_ID=$(az account show --query tenantId -o tsv)

# ---- 4) GitHub repo variables (no secrets needed with OIDC) ----
gh variable set AZURE_CLIENT_ID       -b "$APP_ID"          -R "$REPO"
gh variable set AZURE_TENANT_ID       -b "$TENANT_ID"       -R "$REPO"
gh variable set AZURE_SUBSCRIPTION_ID -b "$SUBSCRIPTION_ID"  -R "$REPO"
gh variable set TF_STATE_RG           -b "$STATE_RG"        -R "$REPO"
gh variable set TF_STATE_SA           -b "$STATE_SA"        -R "$REPO"
gh variable set TF_STATE_CONTAINER    -b "$STATE_CONTAINER"  -R "$REPO"
gh variable set ADMIN_SOURCE_IP       -b "$(curl -s ifconfig.me)/32" -R "$REPO"
gh variable set SSH_PUBLIC_KEY        -b "$(cat ~/.ssh/id_rsa.pub)"  -R "$REPO"

echo "STATE_SA=$STATE_SA   (put this in your backend.hcl files)"
```

## Databricks workspace access for the SP

Stage 2 manages the workspace through the Databricks provider using this SP's
Azure identity. Granting it **Contributor** on the subscription (above) makes it
a workspace admin on the workspaces it creates, which is enough for the POC. If
cluster creation returns a permissions error, add the SP as a workspace admin
explicitly (Workspace → Settings → Identity and access → Service principals).

## Create the gated environment

In GitHub: **Settings → Environments → New environment → `azure-poc`**, and add
yourself as a **Required reviewer**. The apply workflow targets this environment,
so every apply pauses for your approval.

## Local use (same backend)

```bash
cp terraform/1-foundation/backend.hcl.example terraform/1-foundation/backend.hcl  # set STATE_SA
cd terraform/1-foundation && terraform init -backend-config=backend.hcl
```
