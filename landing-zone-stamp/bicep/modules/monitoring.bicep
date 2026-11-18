// =============================================================================
// monitoring.bicep  (SKELETON)
// Log Analytics workspace and the platform action group.
// Long-term, tamper-proof retention is handled by the log archive in
// security-assessment-toolkit/logging (immutable storage), not here.
// =============================================================================
param namePrefix string
param location string
param tags object
param alertEmail string
param retentionDays int

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${namePrefix}-log-01'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionDays
    features: {
      disableLocalAuth: true
    }
  }
}

// Action group short names are limited to 12 characters, so the name is
// built from a fixed string rather than cut from the prefix.
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: '${namePrefix}-ag-01'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'plat-alerts'
    enabled: true
    emailReceivers: [
      {
        name: 'platform-mailbox'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

output workspaceId string = workspace.id
output actionGroupId string = actionGroup.id
