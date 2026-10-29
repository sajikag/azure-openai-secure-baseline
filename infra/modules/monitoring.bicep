// Log Analytics workspace that receives audit and request logs from
// Azure OpenAI and Key Vault. Optionally onboards Microsoft Sentinel.

param name string
param location string
param tags object

@minValue(30)
@maxValue(730)
param retentionInDays int

@description('Onboard Microsoft Sentinel on the workspace (adds cost).')
param enableSentinel bool

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
  }
}

resource sentinel 'Microsoft.SecurityInsights/onboardingStates@2024-03-01' = if (enableSentinel) {
  name: 'default'
  scope: workspace
  properties: {}
}

output workspaceId string = workspace.id
