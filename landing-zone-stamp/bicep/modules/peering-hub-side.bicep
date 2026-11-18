// =============================================================================
// peering-hub-side.bicep  (SKELETON)
// The hub half of a hub-to-spoke peering. Deployed into the hub resource group.
// =============================================================================
param hubVnetName string
param spokeVnetId string
param peeringName string

resource hub 'Microsoft.Network/virtualNetworks@2024-01-01' existing = {
  name: hubVnetName
}

resource toSpoke 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-01-01' = {
  parent: hub
  name: peeringName
  properties: {
    remoteVirtualNetwork: {
      id: spokeVnetId
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
  }
}
