// =============================================================================
// main.foundation.bicep  (SKELETON)
// The shared platform every customer stamp plugs into:
//   - platform resource group : Log Analytics workspace, action group
//   - hub resource group      : hub virtual network, WAF policy, private DNS
//
// Deploy (once per product and region):
//   az deployment sub create --location eastus2 \
//     --template-file main.foundation.bicep --parameters @foundation.example.bicepparam
//
// Naming: <product>-<workload>-<env>-<region>-<type>-<nn>
//   e.g. contoso-hub-prd-eus2-vnet-01   (see ../docs/naming.md)
// =============================================================================
targetScope = 'subscription'

@maxLength(8)
param product string

@allowed([
  'dev'
  'tst'
  'prd'
])
param env string = 'prd'

param location string = 'eastus2'

@description('Short region code used in names, e.g. eus2.')
@maxLength(5)
param regionCode string = 'eus2'

@description('Hub address space. Stamps take ranges outside it.')
param hubAddressPrefix string = '10.10.0.0/22'

@description('Where platform alerts go. Use a shared mailbox, never a person.')
param alertEmail string

@description('Log Analytics retention in days for the interactive tier.')
@minValue(30)
param logRetentionDays int = 90

var tags = {
  product: product
  env: env
  managedBy: 'bicep'
}

resource platformRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: '${product}-plat-${env}-${regionCode}-rg-01'
  location: location
  tags: tags
}

resource hubRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: '${product}-hub-${env}-${regionCode}-rg-01'
  location: location
  tags: tags
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  scope: platformRg
  params: {
    namePrefix: '${product}-plat-${env}-${regionCode}'
    location: location
    tags: tags
    alertEmail: alertEmail
    retentionDays: logRetentionDays
  }
}

module hub 'modules/hub.bicep' = {
  name: 'hub'
  scope: hubRg
  params: {
    namePrefix: '${product}-hub-${env}-${regionCode}'
    location: location
    tags: tags
    addressPrefix: hubAddressPrefix
  }
}

output platformResourceGroup string = platformRg.name
output hubResourceGroup string = hubRg.name
output hubVnetName string = hub.outputs.vnetName
output hubVnetId string = hub.outputs.vnetId
output workspaceId string = monitoring.outputs.workspaceId
output actionGroupId string = monitoring.outputs.actionGroupId
output keyVaultDnsZoneId string = hub.outputs.keyVaultDnsZoneId
output hubGatewaySubnetPrefix string = hub.outputs.gatewaySubnetPrefix
