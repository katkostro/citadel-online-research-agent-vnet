/*
Existing VNet Subnet Provisioning Module
Ensures required subnets exist in an existing Virtual Network:

Subnets Managed:
- Agent subnet (AI Services network injection with delegation)
- ACA subnet (Container Apps Environment infrastructure)  
- Private Endpoint subnet (secure connectivity)

Behavior:
- Creates missing subnets if they don't exist
- Uses explicit address prefixes or calculates defaults
- Supports cross-subscription and cross-resource group scenarios
*/

@description('The name of the existing virtual network')
param vnetName string

@description('Subscription ID of the VNet (if different from current)')
param vnetSubscriptionId string = subscription().subscriptionId

@description('Resource Group name of the VNet (if different from current)')
param vnetResourceGroupName string = resourceGroup().name

@description('The name of AI Services agent subnet')
param agentSubnetName string = 'agent-subnet'

@description('The name of Container Apps infrastructure subnet')
param acaSubnetName string = 'aca-subnet'

@description('The name of Private Endpoint subnet')
param peSubnetName string = 'pe-subnet'

@description('Address prefix for the agent subnet (required if subnet does not exist)')
param agentSubnetPrefix string = ''

@description('Address prefix for the ACA subnet (required if subnet does not exist)')
param acaSubnetPrefix string = ''

@description('Address prefix for the private endpoint subnet (required if subnet does not exist)')
param peSubnetPrefix string = ''

// Reference the existing VNet
resource existingVNet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: vnetName
  scope: resourceGroup(vnetResourceGroupName)
}

// Get VNet address space for automatic subnet calculation
var vnetAddressSpace = existingVNet.properties.addressSpace.addressPrefixes[0]

// Calculate default subnet addresses if not provided (assumes /16 VNet)
var agentSubnetSpaces = empty(agentSubnetPrefix) ? cidrSubnet(vnetAddressSpace, 8, 0) : agentSubnetPrefix  // /24 at .0.0
var peSubnetSpaces = empty(peSubnetPrefix) ? cidrSubnet(vnetAddressSpace, 8, 1) : peSubnetPrefix          // /24 at .1.0
var acaSubnetSpaces = empty(acaSubnetPrefix) ? cidrSubnet(vnetAddressSpace, 7, 1) : acaSubnetPrefix       // /23 at .2.0-.3.255

// Agent subnet with delegation for AI Services network injection
module agentSubnet 'subnet.bicep' = {
  name: 'agent-subnet-${uniqueString(deployment().name, agentSubnetName)}'
  scope: resourceGroup(vnetResourceGroupName)
  params: {
    vnetName: vnetName
    subnetName: agentSubnetName
    addressPrefix: agentSubnetSpaces
    delegations: [
      {
        name: 'Microsoft.App/environments'
        properties: {
          serviceName: 'Microsoft.App/environments'
        }
      }
    ]
  }
}

// Container Apps Environment infrastructure subnet
module acaSubnet 'subnet.bicep' = {
  name: 'aca-subnet-${uniqueString(deployment().name, acaSubnetName)}'
  scope: resourceGroup(vnetResourceGroupName)
  params: {
    vnetName: vnetName
    subnetName: acaSubnetName
    addressPrefix: acaSubnetSpaces
    delegations: []
  }
}

// Private Endpoint subnet
module peSubnet 'subnet.bicep' = {
  name: 'pe-subnet-${uniqueString(deployment().name, peSubnetName)}'
  scope: resourceGroup(vnetResourceGroupName)
  params: {
    vnetName: vnetName
    subnetName: peSubnetName
    addressPrefix: peSubnetSpaces
    delegations: []
  }
}

// Outputs
output virtualNetworkName string = existingVNet.name
output virtualNetworkId string = existingVNet.id
output virtualNetworkResourceGroup string = vnetResourceGroupName
output virtualNetworkSubscriptionId string = vnetSubscriptionId

output agentSubnetName string = agentSubnetName
output agentSubnetId string = '${existingVNet.id}/subnets/${agentSubnetName}'

output acaSubnetName string = acaSubnetName
output acaSubnetId string = '${existingVNet.id}/subnets/${acaSubnetName}'

output peSubnetName string = peSubnetName
output peSubnetId string = '${existingVNet.id}/subnets/${peSubnetName}'
