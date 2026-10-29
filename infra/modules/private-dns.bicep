// Private DNS zone linked to the virtual network, so the service's public
// hostname resolves to its private endpoint IP from inside the VNet.

@description('Private DNS zone name, e.g. privatelink.openai.azure.com')
param zoneName string

param vnetId string
param vnetName string
param tags object

resource zone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: zoneName
  location: 'global'
  tags: tags
}

resource link 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: zone
  name: '${vnetName}-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

output zoneId string = zone.id
