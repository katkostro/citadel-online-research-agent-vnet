@description('Primary (local) VNet name to which remote VNet will be peered')
param primaryVnetName string
@description('Primary VNet resource group name')
param primaryVnetResourceGroupName string
@description('Primary VNet subscription ID')
param primaryVnetSubscriptionId string

@description('Remote (peer) VNet resource ID')
param remoteVnetResourceId string

@description('Create the peering from primary -> remote')
param createPrimaryToRemote bool = true
@description('Create the peering from remote -> primary (needs permission on remote)')
param createRemoteToPrimary bool = false

@description('Enable forwarded traffic on primary->remote peering')
param allowForwardedTraffic bool = true
@description('Allow gateway transit primary->remote')
param allowGatewayTransit bool = false
@description('Use remote gateways on primary->remote')
param useRemoteGateways bool = false

@description('Enable forwarded traffic on remote->primary peering')
param remoteAllowForwardedTraffic bool = true
@description('Allow gateway transit remote->primary')
param remoteAllowGatewayTransit bool = false
@description('Use remote gateways on remote->primary')
param remoteUseRemoteGateways bool = false

var remoteParts = split(remoteVnetResourceId, '/')
var remoteVnetName = last(remoteParts)

// Compose VNet IDs (module is deployed at primary VNet resource group scope by caller)
var primaryVnetId = '/subscriptions/${primaryVnetSubscriptionId}/resourceGroups/${primaryVnetResourceGroupName}/providers/Microsoft.Network/virtualNetworks/${primaryVnetName}'
var remoteVnetId = remoteVnetResourceId

// Peering from primary to remote
// Peering created on the primary VNet side
resource primaryVnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: primaryVnetName
}

resource primaryToRemotePeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = if (createPrimaryToRemote) {
  name: 'to-${remoteVnetName}'
  parent: primaryVnet
  properties: {
    remoteVirtualNetwork: {
      id: remoteVnetId
    }
    allowForwardedTraffic: allowForwardedTraffic
    allowGatewayTransit: allowGatewayTransit
    useRemoteGateways: useRemoteGateways
    allowVirtualNetworkAccess: true
  }
}

// Peering from remote to primary (requires access to remote RG)
// Reverse peering performed via deployment script (cross-RG/subscription) if enabled
resource reversePeeringScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = if (createRemoteToPrimary) {
  name: 'create-remote-peering-${uniqueString(primaryVnetId, remoteVnetId)}'
  location: resourceGroup().location
  kind: 'AzureCLI'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    azCliVersion: '2.62.0'
    timeout: 'PT10M'
    retentionInterval: 'P1D'
    scriptContent: '''
set -euo pipefail
echo "Creating/ensuring reverse peering (remote -> primary)..."
REMOTE_VNET_ID="${REMOTE_VNET_ID}" # full id
PRIMARY_VNET_ID="${PRIMARY_VNET_ID}" # full id

# Parse remote RG and name
REMOTE_RG=$(echo "$REMOTE_VNET_ID" | cut -d'/' -f5)
REMOTE_VNET_NAME=$(basename "$REMOTE_VNET_ID")
PRIMARY_VNET_NAME=$(basename "$PRIMARY_VNET_ID")

PEERING_NAME="to-${PRIMARY_VNET_NAME}"
echo "Remote RG: $REMOTE_RG  Remote VNet: $REMOTE_VNET_NAME  Peering Name: $PEERING_NAME"

if az network vnet peering show -g "$REMOTE_RG" --vnet-name "$REMOTE_VNET_NAME" -n "$PEERING_NAME" >/dev/null 2>&1; then
  echo "Reverse peering already exists. Skipping create."
else
  az network vnet peering create -g "$REMOTE_RG" --vnet-name "$REMOTE_VNET_NAME" -n "$PEERING_NAME" \
    --remote-vnet "$PRIMARY_VNET_ID" \
    --allow-vnet-access \
    ${REMOTE_ALLOW_FORWARDED:+--allow-forwarded-traffic} \
    ${REMOTE_ALLOW_GATEWAY_TRANSIT:+--allow-gateway-transit} \
    ${REMOTE_USE_REMOTE_GATEWAYS:+--use-remote-gateways}
  echo "Reverse peering created."
fi
'''
    environmentVariables: [
      {
        name: 'REMOTE_VNET_ID'
        value: remoteVnetId
      }
      {
        name: 'PRIMARY_VNET_ID'
        value: primaryVnetId
      }
      {
        name: 'REMOTE_ALLOW_FORWARDED'
        value: string(remoteAllowForwardedTraffic)
      }
      {
        name: 'REMOTE_ALLOW_GATEWAY_TRANSIT'
        value: string(remoteAllowGatewayTransit)
      }
      {
        name: 'REMOTE_USE_REMOTE_GATEWAYS'
        value: string(remoteUseRemoteGateways)
      }
    ]
  }
  dependsOn: [
    primaryToRemotePeering
  ]
}

output primaryToRemotePeeringName string = createPrimaryToRemote ? 'to-${remoteVnetName}' : ''
output remoteToPrimaryPeeringName string = createRemoteToPrimary ? 'to-${primaryVnetName}' : ''
output remoteVnetName string = remoteVnetName
