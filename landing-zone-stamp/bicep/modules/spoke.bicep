// =============================================================================
// spoke.bicep  (SKELETON)
// Stamp network: spoke VNet, NSG, NAT gateway, and the spoke side of peering.
//
// Inbound : only the hub gateway subnet may reach the app port. No public IPs on NICs.
// Outbound: a NAT gateway gives one predictable egress IP, and the NSG allows
//           HTTPS only to Azure service tags plus an explicit allow-list.
//           "Outbound 443 to anywhere" is the common gap this closes.
// =============================================================================
param namePrefix string
param location string
param tags object
param addressPrefix string
param appPort int
param gatewaySubnetPrefix string
param egressAllowedPrefixes array
param hubVnetId string

var appSubnet = cidrSubnet(addressPrefix, 25, 0)
var endpointSubnet = cidrSubnet(addressPrefix, 27, 4)

var baseRules = [
  {
    name: 'in-allow-gateway-to-app'
    properties: {
      priority: 200
      direction: 'Inbound'
      access: 'Allow'
      protocol: 'Tcp'
      sourceAddressPrefix: gatewaySubnetPrefix
      sourcePortRange: '*'
      destinationAddressPrefix: appSubnet
      destinationPortRange: string(appPort)
    }
  }
  {
    name: 'in-deny-all'
    properties: {
      priority: 4000
      direction: 'Inbound'
      access: 'Deny'
      protocol: '*'
      sourceAddressPrefix: '*'
      sourcePortRange: '*'
      destinationAddressPrefix: '*'
      destinationPortRange: '*'
    }
  }
  {
    name: 'out-allow-azure-services'
    properties: {
      priority: 200
      direction: 'Outbound'
      access: 'Allow'
      protocol: 'Tcp'
      sourceAddressPrefix: 'VirtualNetwork'
      sourcePortRange: '*'
      // Skeleton uses one broad tag. Full build: one rule each for
      // AzureKeyVault, Storage, AzureMonitor and AzureActiveDirectory.
      destinationAddressPrefix: 'AzureCloud'
      destinationPortRange: '443'
    }
  }
  {
    name: 'out-deny-internet'
    properties: {
      priority: 4000
      direction: 'Outbound'
      access: 'Deny'
      protocol: '*'
      sourceAddressPrefix: '*'
      sourcePortRange: '*'
      destinationAddressPrefix: 'Internet'
      destinationPortRange: '*'
    }
  }
]

// Optional allow-list for vendor endpoints, inserted between the two outbound rules.
var vendorRule = empty(egressAllowedPrefixes) ? [] : [
  {
    name: 'out-allow-vendor-https'
    properties: {
      priority: 300
      direction: 'Outbound'
      access: 'Allow'
      protocol: 'Tcp'
      sourceAddressPrefix: appSubnet
      sourcePortRange: '*'
      destinationAddressPrefixes: egressAllowedPrefixes
      destinationPortRange: '443'
    }
  }
]

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: '${namePrefix}-nsg-01'
  location: location
  tags: tags
  properties: {
    securityRules: concat(baseRules, vendorRule)
  }
}

resource natIp 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: '${namePrefix}-pip-nat-01'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource nat 'Microsoft.Network/natGateways@2024-01-01' = {
  name: '${namePrefix}-ng-01'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIpAddresses: [
      {
        id: natIp.id
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: '${namePrefix}-vnet-01'
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
        name: 'snet-app'
        properties: {
          addressPrefix: appSubnet
          networkSecurityGroup: {
            id: nsg.id
          }
          natGateway: {
            id: nat.id
          }
          defaultOutboundAccess: false
        }
      }
      {
        name: 'snet-pe'
        properties: {
          addressPrefix: endpointSubnet
          networkSecurityGroup: {
            id: nsg.id
          }
          privateEndpointNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

resource toHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-01-01' = {
  parent: vnet
  name: 'to-hub'
  properties: {
    remoteVirtualNetwork: {
      id: hubVnetId
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    useRemoteGateways: false
  }
}

output vnetId string = vnet.id
output appSubnetId string = vnet.properties.subnets[0].id
output endpointSubnetId string = vnet.properties.subnets[1].id
output natPublicIp string = natIp.properties.ipAddress
