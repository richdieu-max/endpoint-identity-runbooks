// =============================================================================
// backup.bicep  (SKELETON)
// Recovery Services vault for the stamp VM.
//
//   - geo-redundant, cross-region restore on
//   - soft delete always on
//   - immutability ENABLED BUT UNLOCKED. Locking cannot be undone, so it is a
//     decision for the system owner, made in writing, not a build default.
//   - public network access disabled
//
// Enrolling the VM (backup policy + protected item) is left to the build
// script, because the first backup also needs the restore-point resource group
// to exist with the right tags if tag policies are enforced.
// =============================================================================
param namePrefix string
param location string
param tags object

resource rsv 'Microsoft.RecoveryServices/vaults@2024-04-01' = {
  name: '${namePrefix}-rsv-01'
  location: location
  tags: tags
  sku: {
    name: 'RS0'
    tier: 'Standard'
  }
  properties: {
    publicNetworkAccess: 'Disabled'
    redundancySettings: {
      standardTierStorageRedundancy: 'GeoRedundant'
      crossRegionRestore: 'Enabled'
    }
    securitySettings: {
      immutabilitySettings: {
        state: 'Unlocked'
      }
      softDeleteSettings: {
        softDeleteState: 'AlwaysON'
        softDeleteRetentionPeriodInDays: 14
      }
    }
  }
}

output vaultName string = rsv.name
