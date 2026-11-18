// =============================================================================
// main.tenant.bicep  (SKELETON)
// Management group hierarchy for one product.
//
//   <tenant root>
//     └─ <org>-<product>                      product root
//          ├─ <org>-<product>-platform        shared foundation (hub, logs)
//          ├─ <org>-<product>-customers       one subscription per stamp, or shared
//          ├─ <org>-<product>-sandbox         experiments, looser policy
//          └─ <org>-<product>-decommissioned  parked, deny-all
//
// Deploy:
//   az deployment tenant create --location eastus2 \
//     --template-file main.tenant.bicep --parameters org=org product=contoso
//
// Needs: rights to create management groups under the parent. If the tenant
// restricts management group creation, the preflight script reports it as a gate.
// =============================================================================
targetScope = 'tenant'

@description('Short organisation prefix used on management groups and security groups.')
@maxLength(6)
param org string

@description('Product name. Every resource name carries it.')
@maxLength(8)
param product string

@description('Parent management group. Leave as the tenant root unless the tenant nests products.')
param parentManagementGroupId string = tenant().tenantId

var root = '${org}-${product}'
var children = [
  'platform'
  'customers'
  'sandbox'
  'decommissioned'
]

resource productRoot 'Microsoft.Management/managementGroups@2023-04-01' = {
  name: root
  properties: {
    displayName: root
    details: {
      parent: {
        id: tenantResourceId('Microsoft.Management/managementGroups', parentManagementGroupId)
      }
    }
  }
}

resource childGroups 'Microsoft.Management/managementGroups@2023-04-01' = [for c in children: {
  name: '${root}-${c}'
  properties: {
    displayName: '${root}-${c}'
    details: {
      parent: {
        id: productRoot.id
      }
    }
  }
}]

// Guardrails are assigned at the product root so every child inherits them.
module guardrails 'modules/guardrails.bicep' = {
  name: 'guardrails-${root}'
  scope: managementGroup(productRoot.name)
  params: {
    allowedLocations: [
      'eastus2'
      'centralus'
    ]
  }
}

output productRootId string = productRoot.id
output childGroupIds array = [for (c, i) in children: childGroups[i].id]
