<#
.SYNOPSIS
  Deletes the resource group created by deploy.ps1.

.NOTES
  - Key Vault has purge protection: its name stays reserved for 90 days.
  - The Azure OpenAI account is soft-deleted for 48 hours. To reuse the same
    name sooner, purge it:
      az cognitiveservices account purge --name <name> --resource-group <rg> --location <region>
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ResourceGroup
)

$ErrorActionPreference = 'Stop'

az group show --name $ResourceGroup -o none 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Resource group '$ResourceGroup' not found. Nothing to do."
    return
}

Write-Warning "This permanently deletes every resource in '$ResourceGroup'."
$confirm = Read-Host "Type the resource group name to confirm"
if ($confirm -ne $ResourceGroup) {
    Write-Host 'Names did not match. Aborted.'
    return
}

az group delete --name $ResourceGroup --yes --no-wait
if ($LASTEXITCODE -ne 0) { throw 'Delete request failed.' }
Write-Host "Deletion of '$ResourceGroup' started. It may take several minutes."
