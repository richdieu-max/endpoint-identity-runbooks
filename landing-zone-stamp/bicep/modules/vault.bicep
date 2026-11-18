// =============================================================================
// vault.bicep  (SKELETON)
// Per-stamp Key Vault, customer-managed disk key, disk encryption set,
// private endpoint, and audit logging.
//
//   - RBAC authorisation only (no access policies)
//   - purge protection on, soft delete 90 days
//   - public network access DISABLED: reachable only through the private endpoint
//   - every read and write logged to the platform workspace
//
// Consequence worth knowing: with public access disabled, seeding secrets needs
// an in-network path (a jump host, a pipeline agent in the VNet) or a short,
// recorded "selected networks" window. Plan for it before go-live.
// =============================================================================
param namePrefix string

@description('Key Vault names are global and limited to 24 characters.')
@maxLength(21)
param shortName string

param location string
param tags object
param endpointSubnetId string
param keyVaultDnsZoneId string
param workspaceId string

// Built-in role: Key Vault Crypto Service Encryption User
var cryptoServiceEncryptionUser = 'e147488a-f6f5-4113-8e2d-b22465e65bf6'

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: '${shortName}-kv'
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'premium'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

resource diskKey 'Microsoft.KeyVault/vaults/keys@2023-07-01' = {
  parent: kv
  name: 'disk-cmk-01'
  properties: {
    kty: 'RSA-HSM'
    keySize: 3072
    rotationPolicy: {
      lifetimeActions: [
        {
          trigger: {
            timeBeforeExpiry: 'P30D'
          }
          action: {
            type: 'rotate'
          }
        }
      ]
      attributes: {
        expiryTime: 'P1Y'
      }
    }
  }
}

resource des 'Microsoft.Compute/diskEncryptionSets@2023-04-02' = {
  name: '${namePrefix}-des-01'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    encryptionType: 'EncryptionAtRestWithCustomerKey'
    rotationToLatestKeyVersionEnabled: true
    activeKey: {
      keyUrl: diskKey.properties.keyUri
      sourceVault: {
        id: kv.id
      }
    }
  }
}

resource desCanUseKey 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kv.id, des.id, cryptoServiceEncryptionUser)
  scope: kv
  properties: {
    principalId: des.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cryptoServiceEncryptionUser)
  }
}

resource pe 'Microsoft.Network/privateEndpoints@2024-01-01' = {
  name: '${namePrefix}-pe-kv-01'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: endpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'kv'
        properties: {
          privateLinkServiceId: kv.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
}

resource peDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = {
  parent: pe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'vault'
        properties: {
          privateDnsZoneId: keyVaultDnsZoneId
        }
      }
    ]
  }
}

resource kvAudit 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'to-platform-workspace'
  scope: kv
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        categoryGroup: 'audit'
        enabled: true
      }
    ]
  }
}

// TODO (full build): link the stamp VNet to the shared private DNS zone so the
// VM resolves the vault's private address.

output keyVaultName string = kv.name
output keyVaultId string = kv.id
output diskEncryptionSetId string = des.id
