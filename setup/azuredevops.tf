# Create ADO objects for pipeline

provider "azuredevops" {
  org_service_url = var.ado_org_service_url
  # Authentication through PAT defined with AZDO_PERSONAL_ACCESS_TOKEN 
}

resource "azuredevops_project" "project" {
  name               = local.ado_project_name
  description        = local.ado_project_description
  visibility         = local.ado_project_visibility
  version_control    = "Git"   # This will always be Git for me
  work_item_template = "Agile" # Not sure if this matters, check back later

  features = {
    # Only enable pipelines for now
    "testplans"    = "disabled"
    "artifacts"    = "disabled"
    "boards"       = "disabled"
    "repositories" = "enabled"
    "pipelines"    = "enabled"
  }
}

resource "azuredevops_git_repository" "new_repo" {
  project_id = azuredevops_project.project.id
  name       = var.ado_azrepo_name
  initialization {
    init_type = "Clean" # Options: Uninitialized, Clean, or Import
  }
}

resource "azuredevops_git_repository" "existing_repo" {
  project_id = azuredevops_project.project.id
  name       = "Repo Import Test"
  initialization {
    init_type = "Import" #Options: Uninitialized, Clean, or Import
    source_type = "Git" # Type type of the source repository. Used if the init_type is Import.
    source_url = "https://github.com/v-it-azure/iac-ado-azrepo/" # The URL of the source repository. Used if the init_type is Import.
  }
 }

resource "azuredevops_serviceendpoint_github" "serviceendpoint_github" {
  project_id            = azuredevops_project.project.id
  service_endpoint_name = "ado-github"

  auth_personal {
    personal_access_token = var.ado_github_pat
  }
}

resource "azuredevops_resource_authorization" "auth" {
  project_id  = azuredevops_project.project.id
  resource_id = azuredevops_serviceendpoint_github.serviceendpoint_github.id
  authorized  = true
}

resource "azuredevops_variable_group" "variablegroup" {
  project_id   = azuredevops_project.project.id
  name         = "ado-azrepo"
  description  = "Variable group for pipelines"
  allow_access = true

  variable {
    name  = "service_name"
    value = "key_vault"
  }

  variable {
    name = "key_vault_name"
    value = local.az_key_vault_name
  }

}

resource "azuredevops_build_definition" "pipeline_1" {

  depends_on = [azuredevops_resource_authorization.auth]
  project_id = azuredevops_project.project.id
  name       = local.ado_pipeline_name_1

  ci_trigger {
    use_yaml = true
  }

  repository {
    repo_type             = "TfsGit"
    repo_id               = azuredevops_git_repository.existing_repo.id
    branch_name           = "main"
    yml_path              = var.ado_pipeline_yaml_path_1
  }

}

# Key Vault setup
## There needs to be a service connection to an Azure sub with the key vault
## https://registry.terraform.io/providers/microsoft/azuredevops/latest/docs/resources/serviceendpoint_azurerm

resource "azuredevops_serviceendpoint_azurerm" "key_vault" {
  project_id = azuredevops_project.project.id
  service_endpoint_name = "key_vault"
  description = "Azure Service Endpoint for Key Vault Access"

  credentials {
    serviceprincipalid = azuread_application.service_connection.application_id
    serviceprincipalkey = random_password.service_connection.result
  }

  azurerm_spn_tenantid = data.azurerm_client_config.current.tenant_id
  azurerm_subscription_id = data.azurerm_client_config.current.subscription_id
  azurerm_subscription_name = data.azurerm_subscription.current.display_name
}

resource "azuredevops_resource_authorization" "kv_auth" {
  project_id  = azuredevops_project.project.id
  resource_id = azuredevops_serviceendpoint_azurerm.key_vault.id
  authorized  = true
}

# Key Vault task is here: https://docs.microsoft.com/en-us/azure/devops/pipelines/tasks/deploy/azure-key-vault?view=azure-devops

