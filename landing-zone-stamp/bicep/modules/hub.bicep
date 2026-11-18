// =============================================================================
// hub.bicep  (SKELETON)
// Hub virtual network, WAF policy and the private DNS zone stamps share.
//
// The Application Gateway itself is NOT built here. It needs a public
// hostname and a TLS certificate, which usually arrive after the first run.
// Build the WAF policy now (Prevention mode), attach it when the gateway lands.
// =============================================================================
param namePrefix string
param location string
param tags object
param addressPrefix string

// Carve the hub range into fixed subnets: /24 gateway, /26 private endpoints.
var gatewaySubnet = cidrSubnet(addressPrefix, 24, 0)
var endpointSubnet = cidrSubnet(addressPrefix, 26, 4)

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
        name: 'snet-appgw'
        properties: {
          addressPrefix: gatewaySubnet
        }
      }
      {
        name: 'snet-pe'
        properties: {
          addressPrefix: endpointSubnet
          privateEndpointNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

resource wafPolicy 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2024-01-01' = {
  name: '${namePrefix}-waf-01'
  location: location
  tags: tags
  properties: {
    policySettings: {
      state: 'Enabled'
      mode: 'Prevention'
      requestBodyCheck: true
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'Microsoft_DefaultRuleSet'
          ruleSetVersion: '2.1'
        }
      ]
    }
    // TODO (full build): custom Allow rules for webhook paths that the managed
    // rules would block, each scoped to the narrowest path and source.
  }
}

// Private DNS zone for Key Vault private endpoints. Stamps link their own VNets.
#disable-next-line no-hardcoded-env-urls
var kvZoneName = 'privatelink.vaultcore.azure.net'

resource kvZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: kvZoneName
  location: 'global'
  tags: tags
}

resource kvZoneHubLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: kvZone
  name: '${namePrefix}-vnet-01-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

output vnetName string = vnet.name
output vnetId string = vnet.id
output wafPolicyId string = wafPolicy.id
output gatewaySubnetPrefix string = gatewaySubnet
output keyVaultDnsZoneId string = kvZone.id
