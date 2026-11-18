// =============================================================================
// vm.bicep  (SKELETON)
// The stamp's workload VM.
//
//   - Ubuntu LTS, Trusted Launch (secure boot + vTPM), encryption at host
//   - no public IP; reached through the gateway (users) or a private path (admins)
//   - SSH keys only, password sign-in disabled
//   - data disk encrypted with the stamp's customer-managed key
//   - system-assigned identity with READ-ONLY access to the stamp's secrets
//     (Key Vault Secrets User). The service fetches secrets at start-up;
//     see ../../vm-secrets-at-start.
// =============================================================================
param namePrefix string
param location string
param tags object
param subnetId string
param vmSize string
param adminUsername string
param sshPublicKey string
param diskEncryptionSetId string
param keyVaultName string

// Built-in role: Key Vault Secrets User (read secret values, nothing else)
var keyVaultSecretsUser = '4633458b-17de-408a-b874-0445c86b69e6'

resource nic 'Microsoft.Network/networkInterfaces@2024-01-01' = {
  name: '${namePrefix}-nic-01'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetId
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: '${namePrefix}-vm-01'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      encryptionAtHost: true
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
    osProfile: {
      computerName: take(replace('${namePrefix}-vm-01', '-', ''), 15)
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
        patchSettings: {
          patchMode: 'AutomaticByPlatform'
          assessmentMode: 'AutomaticByPlatform'
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        name: '${namePrefix}-osdisk-01'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
          diskEncryptionSet: {
            id: diskEncryptionSetId
          }
        }
      }
      dataDisks: [
        {
          name: '${namePrefix}-datadisk-01'
          lun: 0
          createOption: 'Empty'
          diskSizeGB: 64
          managedDisk: {
            storageAccountType: 'Premium_LRS'
            diskEncryptionSet: {
              id: diskEncryptionSetId
            }
          }
        }
      ]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource vmReadsSecrets 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kv.id, vm.id, keyVaultSecretsUser)
  scope: kv
  properties: {
    principalId: vm.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUser)
  }
}

output vmName string = vm.name
output principalId string = vm.identity.principalId
