// Virtual network with two subnets:
//   snet-private-endpoints : private endpoints for Azure OpenAI and Key Vault only
//   snet-workload          : where the calling application runs
// The private-endpoint subnet accepts HTTPS from the workload subnet and nothing else.

@description('Virtual network name.')
param name string

param location string
param tags object

param addressPrefix string
param privateEndpointSubnetPrefix string
param workloadSubnetPrefix string

var peSubnetName = 'snet-private-endpoints'
var workloadSubnetName = 'snet-workload'

resource peNsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: '${name}-pe-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-Workload-HTTPS-Inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: workloadSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: privateEndpointSubnetPrefix
          destinationPortRange: '443'
        }
      }
      {
        // Overrides the default AllowVnetInBound rule (priority 65000)
        name: 'Deny-All-Other-Inbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource workloadNsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: '${name}-workload-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [
      {
        name: peSubnetName
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          networkSecurityGroup: {
            id: peNsg.id
          }
          // Required so the NSG above is actually enforced on private endpoints
          privateEndpointNetworkPolicies: 'Enabled'
        }
      }
      {
        name: workloadSubnetName
        properties: {
          addressPrefix: workloadSubnetPrefix
          networkSecurityGroup: {
            id: workloadNsg.id
          }
        }
      }
    ]
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output privateEndpointSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, peSubnetName)
output workloadSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, workloadSubnetName)
