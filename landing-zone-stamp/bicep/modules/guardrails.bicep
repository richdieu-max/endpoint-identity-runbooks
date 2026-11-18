// =============================================================================
// guardrails.bicep  (SKELETON)
// Policy assignments at the product root management group.
//
// Two kinds of policy live here, and they are kept apart on purpose:
//   - guardrails  (Deny / Modify)  : the build must never drift from these
//   - benchmarks  (Audit)          : scored, reported, not blocking
// azure-posture-check reports the two separately for the same reason.
//
// The IDs below are Microsoft BUILT-IN policy definitions (public, the same in
// every tenant). Confirm them in your tenant with:
//   az policy definition show --name <guid> --query displayName
// =============================================================================
targetScope = 'managementGroup'

@description('Regions resources may be created in.')
param allowedLocations array

@description('Effect for the storage secure-transfer guardrail.')
@allowed([
  'Audit'
  'Deny'
])
param secureTransferEffect string = 'Deny'

// Built-in: "Allowed locations"
var allowedLocationsDef = '/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c'
// Built-in: "Secure transfer to storage accounts should be enabled"
var secureTransferDef = '/providers/Microsoft.Authorization/policyDefinitions/404c3081-a854-4457-ae30-26a93ef643f9'

resource allowedLocationsAssignment 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'gr-allowed-locations'
  properties: {
    displayName: 'Guardrail: allowed locations'
    policyDefinitionId: allowedLocationsDef
    enforcementMode: 'Default'
    parameters: {
      listOfAllowedLocations: {
        value: allowedLocations
      }
    }
  }
}

resource secureTransferAssignment 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'gr-storage-https'
  properties: {
    displayName: 'Guardrail: storage HTTPS only'
    policyDefinitionId: secureTransferDef
    enforcementMode: 'Default'
    parameters: {
      effect: {
        value: secureTransferEffect
      }
    }
  }
}

// TODO (full build): add the benchmark initiative (Audit only) and the
// Modify policies that add required tags. Keep each in its own assignment so
// a benchmark finding can never be mistaken for guardrail drift.
