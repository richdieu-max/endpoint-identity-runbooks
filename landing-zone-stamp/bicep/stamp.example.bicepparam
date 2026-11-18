// Example values for a FICTIONAL product and its first customer stamp.
// Most values come from the foundation deployment outputs:
//   az deployment sub show -n main.foundation --query properties.outputs
using 'main.stamp.bicep'

param product = 'contoso'
param stampId = 'c001'
param env = 'prd'
param location = 'eastus2'
param regionCode = 'eus2'
param spokeAddressPrefix = '10.20.0.0/24'
param appPort = 8443
param egressAllowedPrefixes = []

param hubResourceGroup = 'contoso-hub-prd-eus2-rg-01'
param hubVnetName = 'contoso-hub-prd-eus2-vnet-01'
param hubVnetId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/contoso-hub-prd-eus2-rg-01/providers/Microsoft.Network/virtualNetworks/contoso-hub-prd-eus2-vnet-01'
param hubGatewaySubnetPrefix = '10.10.0.0/24'
param keyVaultDnsZoneId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/contoso-hub-prd-eus2-rg-01/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net'
param workspaceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/contoso-plat-prd-eus2-rg-01/providers/Microsoft.OperationalInsights/workspaces/contoso-plat-prd-eus2-log-01'

param vmSize = 'Standard_D2s_v5'
param adminUsername = 'azureops'
param sshPublicKey = 'ssh-ed25519 REPLACE-WITH-YOUR-PUBLIC-KEY'
