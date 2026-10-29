// Reusable private endpoint with automatic DNS registration.

param name string
param location string
param tags object

@description('Subnet the private endpoint NIC is placed in.')
param subnetId string

@description('Resource ID of the service being exposed privately.')
param targetResourceId string

@description('Sub-resource: "account" for Azure OpenAI, "vault" for Key Vault.')
param groupId string

@description('Private DNS zone to register the endpoint in.')
param dnsZoneId string

resource pe 'Microsoft.Network/privateEndpoints@2024-01-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: name
        properties: {
          privateLinkServiceId: targetResourceId
          groupIds: [
            groupId
          ]
        }
      }
    ]
  }
}

resource dnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = {
  parent: pe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config'
        properties: {
          privateDnsZoneId: dnsZoneId
        }
      }
    ]
  }
}

output id string = pe.id
