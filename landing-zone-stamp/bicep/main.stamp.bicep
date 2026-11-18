// =============================================================================
// main.stamp.bicep  (SKELETON)
// One customer "stamp": an isolated, identical copy of the workload for one
// customer, plugged into the shared foundation. Deploy it again with a new
// stampId (c002, c003 ...) for the next customer. Nothing is shared between
// stamps except the hub, the logs and the guardrails above them.
//
// Deploy:
//   az deployment sub create --location eastus2 \
//     --template-file main.stamp.bicep --parameters @stamp.example.bicepparam
//
// Run the preflight first (../scripts/Test-StampPreflight.skeleton.ps1).
// Quota, SKU capacity and role conditions are the usual reasons a stamp
// fails half way, and all three are cheaper to find before deploying.
// =============================================================================
targetScope = 'subscription'

@maxLength(8)
param product string

@description('Stamp ID, one per customer: c001, c002 ...')
@minLength(4)
@maxLength(4)
param stampId string

@allowed([
  'dev'
  'tst'
  'prd'
])
param env string = 'prd'

param location string = 'eastus2'

@maxLength(5)
param regionCode string = 'eus2'

@description('Spoke range for this stamp. Must not overlap the hub or other stamps.')
param spokeAddressPrefix string

@description('Port the workload listens on, reachable only from the gateway subnet.')
param appPort int = 8443

@description('Outbound HTTPS destinations the workload genuinely needs (vendor APIs). Everything else on the internet is denied.')
param egressAllowedPrefixes array = []

param hubResourceGroup string
param hubVnetName string
param hubVnetId string
param hubGatewaySubnetPrefix string
param keyVaultDnsZoneId string
param workspaceId string

@description('VM size. Check regional capacity and quota in the preflight; some families are restricted for new subscriptions.')
param vmSize string = 'Standard_D2s_v5'

param adminUsername string = 'azureops'

@description('SSH public key. Password sign-in is disabled.')
param sshPublicKey string

var prefix = '${product}-${stampId}-${env}-${regionCode}'
var tags = {
  product: product
  stamp: stampId
  env: env
  managedBy: 'bicep'
}

resource stampRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: '${prefix}-rg-01'
  location: location
  tags: tags
}

module network 'modules/spoke.bicep' = {
  name: 'spoke-${stampId}'
  scope: stampRg
  params: {
    namePrefix: prefix
    location: location
    tags: tags
    addressPrefix: spokeAddressPrefix
    appPort: appPort
    gatewaySubnetPrefix: hubGatewaySubnetPrefix
    egressAllowedPrefixes: egressAllowedPrefixes
    hubVnetId: hubVnetId
  }
}

// The hub side of the peering lives in the hub resource group.
module hubPeering 'modules/peering-hub-side.bicep' = {
  name: 'peer-hub-${stampId}'
  scope: resourceGroup(hubResourceGroup)
  params: {
    hubVnetName: hubVnetName
    spokeVnetId: network.outputs.vnetId
    peeringName: 'to-${prefix}-vnet-01'
  }
}

module vault 'modules/vault.bicep' = {
  name: 'vault-${stampId}'
  scope: stampRg
  params: {
    namePrefix: prefix
    shortName: '${product}-${stampId}-${env}'
    location: location
    tags: tags
    endpointSubnetId: network.outputs.endpointSubnetId
    keyVaultDnsZoneId: keyVaultDnsZoneId
    workspaceId: workspaceId
  }
}

module vm 'modules/vm.bicep' = {
  name: 'vm-${stampId}'
  scope: stampRg
  params: {
    namePrefix: prefix
    location: location
    tags: tags
    subnetId: network.outputs.appSubnetId
    vmSize: vmSize
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    diskEncryptionSetId: vault.outputs.diskEncryptionSetId
    keyVaultName: vault.outputs.keyVaultName
  }
}

module backup 'modules/backup.bicep' = {
  name: 'backup-${stampId}'
  scope: stampRg
  params: {
    namePrefix: prefix
    location: location
    tags: tags
  }
}

output resourceGroup string = stampRg.name
output vmName string = vm.outputs.vmName
output vmPrincipalId string = vm.outputs.principalId
output keyVaultName string = vault.outputs.keyVaultName
output recoveryVaultName string = backup.outputs.vaultName
