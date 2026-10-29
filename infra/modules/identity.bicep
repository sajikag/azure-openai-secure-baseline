// User-assigned managed identity for the calling workload.
// The workload authenticates to Azure OpenAI and Key Vault with this identity;
// there are no API keys or connection strings to leak.

param name string
param location string
param tags object

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: name
  location: location
  tags: tags
}

output id string = identity.id
output principalId string = identity.properties.principalId
output clientId string = identity.properties.clientId
