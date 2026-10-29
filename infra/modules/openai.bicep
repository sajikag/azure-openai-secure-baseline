// Azure OpenAI account and one model deployment, hardened:
//   - local (API key) auth disabled: Entra ID tokens only
//   - public network access disabled: reachable only through the private endpoint
//   - outbound network access restricted: the service cannot call out to
//     arbitrary URLs (data-exfiltration control)
//   - content filter pinned, model version pinned (no silent upgrades)
//   - all request/audit logs streamed to Log Analytics

param name string
param location string
param tags object

param modelName string
param modelVersion string

@allowed([
  'Standard'
  'GlobalStandard'
  'DataZoneStandard'
])
param deploymentSku string

@description('Throughput cap in thousands of tokens per minute. Also a cost and abuse limit.')
@minValue(1)
param deploymentCapacity int

@description('Principal ID of the workload identity allowed to call the model.')
param workloadPrincipalId string

param logAnalyticsWorkspaceId string

// Built-in role: Cognitive Services OpenAI User (inference only, no management)
var openAiUserRoleId = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'

resource account 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: name
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: name // required for Entra ID auth and private endpoints
    disableLocalAuth: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
    restrictOutboundNetworkAccess: true
    allowedFqdnList: []
  }
}

resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: account
  name: modelName
  sku: {
    name: deploymentSku
    capacity: deploymentCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
    raiPolicyName: 'Microsoft.DefaultV2'
    versionUpgradeOption: 'NoAutoUpgrade'
  }
}

resource inferenceRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(account.id, workloadPrincipalId, openAiUserRoleId)
  scope: account
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', openAiUserRoleId)
    principalId: workloadPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'to-log-analytics'
  scope: account
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output id string = account.id
output name string = account.name
output endpoint string = account.properties.endpoint
output deploymentName string = modelDeployment.name
