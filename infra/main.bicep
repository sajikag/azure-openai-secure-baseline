// azure-openai-secure-baseline
// A locked-down Azure OpenAI deployment: private networking, keyless auth,
// exfiltration controls, centralised audit logging and cost guardrails.
// See docs/threat-model.md for what each control defends against.

targetScope = 'resourceGroup'

// ---------- Naming & placement ----------

@description('Short prefix for resource names. Lowercase letters and numbers, starting with a letter.')
@minLength(3)
@maxLength(10)
param prefix string

@description('Region. Must offer the chosen model and deployment type.')
param location string = resourceGroup().location

param tags object = {
  project: 'azure-openai-secure-baseline'
  managedBy: 'bicep'
}

// ---------- Network ----------

param vnetAddressPrefix string = '10.20.0.0/16'
param privateEndpointSubnetPrefix string = '10.20.1.0/24'
param workloadSubnetPrefix string = '10.20.2.0/24'

// ---------- Model ----------

param modelName string = 'gpt-4o-mini'
param modelVersion string = '2024-07-18'

@description('GlobalStandard may process data in any Azure region; use DataZoneStandard or Standard for data-residency requirements.')
@allowed([
  'Standard'
  'GlobalStandard'
  'DataZoneStandard'
])
param deploymentSku string = 'GlobalStandard'

@description('Thousands of tokens per minute.')
@minValue(1)
param deploymentCapacity int = 10

// ---------- Monitoring ----------

@minValue(30)
@maxValue(730)
param logRetentionInDays int = 90

@description('Onboard Microsoft Sentinel on the Log Analytics workspace (adds cost).')
param enableSentinel bool = false

// ---------- Cost ----------

@description('Monthly budget for the resource group, in the billing currency.')
@minValue(1)
param monthlyBudgetAmount int = 50

@description('Who receives budget alerts.')
@minLength(1)
param budgetContactEmails array

@description('Budget start month. Keep this fixed after the first deployment.')
param budgetStartDate string = utcNow('yyyy-MM-01')

// ---------- Names ----------

var suffix = take(uniqueString(resourceGroup().id), 6)
var openAiName = '${prefix}-aoai-${suffix}'
var keyVaultName = take('${prefix}kv${suffix}', 24)
var openAiDnsZone = 'privatelink.openai.azure.com'
var keyVaultDnsZone = 'privatelink${replace(environment().suffixes.keyvaultDns, 'vault.', 'vaultcore.')}'

// ---------- Modules ----------

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    name: '${prefix}-law'
    location: location
    tags: tags
    retentionInDays: logRetentionInDays
    enableSentinel: enableSentinel
  }
}

module network 'modules/network.bicep' = {
  name: 'network'
  params: {
    name: '${prefix}-vnet'
    location: location
    tags: tags
    addressPrefix: vnetAddressPrefix
    privateEndpointSubnetPrefix: privateEndpointSubnetPrefix
    workloadSubnetPrefix: workloadSubnetPrefix
  }
}

module identity 'modules/identity.bicep' = {
  name: 'identity'
  params: {
    name: '${prefix}-workload-id'
    location: location
    tags: tags
  }
}

module openAiDns 'modules/private-dns.bicep' = {
  name: 'dns-openai'
  params: {
    zoneName: openAiDnsZone
    vnetId: network.outputs.vnetId
    vnetName: network.outputs.vnetName
    tags: tags
  }
}

module keyVaultDns 'modules/private-dns.bicep' = {
  name: 'dns-keyvault'
  params: {
    zoneName: keyVaultDnsZone
    vnetId: network.outputs.vnetId
    vnetName: network.outputs.vnetName
    tags: tags
  }
}

module openAi 'modules/openai.bicep' = {
  name: 'openai'
  params: {
    name: openAiName
    location: location
    tags: tags
    modelName: modelName
    modelVersion: modelVersion
    deploymentSku: deploymentSku
    deploymentCapacity: deploymentCapacity
    workloadPrincipalId: identity.outputs.principalId
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
  }
}

module keyVault 'modules/keyvault.bicep' = {
  name: 'keyvault'
  params: {
    name: keyVaultName
    location: location
    tags: tags
    workloadPrincipalId: identity.outputs.principalId
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
  }
}

module openAiEndpoint 'modules/private-endpoint.bicep' = {
  name: 'pe-openai'
  params: {
    name: '${openAiName}-pe'
    location: location
    tags: tags
    subnetId: network.outputs.privateEndpointSubnetId
    targetResourceId: openAi.outputs.id
    groupId: 'account'
    dnsZoneId: openAiDns.outputs.zoneId
  }
}

module keyVaultEndpoint 'modules/private-endpoint.bicep' = {
  name: 'pe-keyvault'
  params: {
    name: '${keyVaultName}-pe'
    location: location
    tags: tags
    subnetId: network.outputs.privateEndpointSubnetId
    targetResourceId: keyVault.outputs.id
    groupId: 'vault'
    dnsZoneId: keyVaultDns.outputs.zoneId
  }
}

module budget 'modules/budget.bicep' = {
  name: 'budget'
  params: {
    name: '${prefix}-monthly-budget'
    amount: monthlyBudgetAmount
    contactEmails: budgetContactEmails
    startDate: budgetStartDate
  }
}

// ---------- Outputs (no secrets: there are none to output) ----------

output openAiEndpoint string = openAi.outputs.endpoint
output modelDeploymentName string = openAi.outputs.deploymentName
output workloadIdentityResourceId string = identity.outputs.id
output workloadIdentityClientId string = identity.outputs.clientId
output keyVaultName string = keyVault.outputs.name
output workloadSubnetId string = network.outputs.workloadSubnetId
