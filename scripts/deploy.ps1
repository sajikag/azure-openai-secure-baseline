<#
.SYNOPSIS
  Deploys the secure Azure OpenAI baseline into a resource group.

.EXAMPLE
  ./scripts/deploy.ps1 -ResourceGroup rg-aoai-baseline -WhatIf   # preview changes
  ./scripts/deploy.ps1 -ResourceGroup rg-aoai-baseline           # deploy

.NOTES
  Requires Azure CLI 2.53+ (az login first) and Owner or
  Contributor + User Access Administrator on the target subscription,
  because the template creates role assignments.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ResourceGroup,

    [string] $Location = 'swedencentral',

    [string] $ParameterFile = (Join-Path $PSScriptRoot '..' 'infra' 'main.bicepparam'),

    [switch] $WhatIf
)

$ErrorActionPreference = 'Stop'
$template = Join-Path $PSScriptRoot '..' 'infra' 'main.bicep'

function Invoke-Az {
    az @args
    if ($LASTEXITCODE -ne 0) { throw "az $($args -join ' ') failed with exit code $LASTEXITCODE" }
}

Write-Host "Checking Azure CLI sign-in..."
$account = Invoke-Az account show --query '{name:name, id:id}' -o json | ConvertFrom-Json
Write-Host "Subscription: $($account.name) ($($account.id))"

Write-Host "Ensuring resource group '$ResourceGroup' in '$Location'..."
Invoke-Az group create --name $ResourceGroup --location $Location `
    --tags project=azure-openai-secure-baseline --only-show-errors -o none

if ($WhatIf) {
    Invoke-Az deployment group what-if --resource-group $ResourceGroup `
        --template-file $template --parameters $ParameterFile
    return
}

$deploymentName = "aoai-baseline-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Write-Host "Deploying '$deploymentName'..."
$outputs = Invoke-Az deployment group create --resource-group $ResourceGroup `
    --name $deploymentName --template-file $template --parameters $ParameterFile `
    --query properties.outputs -o json | ConvertFrom-Json

Write-Host "`nDeployment complete."
Write-Host "  OpenAI endpoint     : $($outputs.openAiEndpoint.value)"
Write-Host "  Model deployment    : $($outputs.modelDeploymentName.value)"
Write-Host "  Workload identity   : $($outputs.workloadIdentityClientId.value)"
Write-Host "  Key Vault           : $($outputs.keyVaultName.value)"
Write-Host "`nThe endpoint is private. Call it from a resource in the workload subnet"
Write-Host "that runs as the workload identity (see README > Calling the model)."
