/*
DEPRECATED - DO NOT USE THIS FILE
===============================
This file is deprecated and will be removed in a future version.
Use 'networking/existing-vnet-subnets.bicep' instead.

This file should not be referenced in any templates.
*/

@description('The name of the existing virtual network')
param vnetName string

@description('Subscription ID of virtual network (if different from current subscription)')
param vnetSubscriptionId string = subscription().subscriptionId

@description('Resource Group name of the existing VNet (if different from current resource group)')
param vnetResourceGroupName string = resourceGroup().name

@description('The name of Agents Subnet')
param agentSubnetName string = 'agent-subnet'

@description('The name of the Container Apps subnet')
param acaSubnetName string = 'aca-subnet'

@description('The name of Private Endpoint subnet')
param peSubnetName string = 'pe-subnet'

@description('Address prefix for the agent subnet (only needed if creating new subnet)')
param agentSubnetPrefix string = ''

@description('Address prefix for the ACA subnet (only needed if creating new subnet)')
param acaSubnetPrefix string = ''

@description('Address prefix for the private endpoint subnet (only needed if creating new subnet)')
param peSubnetPrefix string = ''

resource existingVNet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: vnetName
  scope: resourceGroup(vnetResourceGroupName)
}

var vnetAddressSpace = existingVNet.properties.addressSpace.addressPrefixes[0]

// Defaults (assumes /16 address space if not provided): agent /24, pe /24, aca /23
var agentSubnetSpaces = empty(agentSubnetPrefix) ? cidrSubnet(vnetAddressSpace, 8, 0) : agentSubnetPrefix
var peSubnetSpaces = empty(peSubnetPrefix) ? cidrSubnet(vnetAddressSpace, 8, 1) : peSubnetPrefix
var acaSubnetSpaces = empty(acaSubnetPrefix) ? cidrSubnet(vnetAddressSpace, 7, 1) : acaSubnetPrefix

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

output peSubnetName string = peSubnetName
output agentSubnetName string = agentSubnetName
output agentSubnetId string = '${existingVNet.id}/subnets/${agentSubnetName}'
output acaSubnetName string = acaSubnetName
output acaSubnetId string = '${existingVNet.id}/subnets/${acaSubnetName}'
output peSubnetId string = '${existingVNet.id}/subnets/${peSubnetName}'
output virtualNetworkName string = existingVNet.name
output virtualNetworkId string = existingVNet.id
output virtualNetworkResourceGroup string = vnetResourceGroupName
output virtualNetworkSubscriptionId string = vnetSubscriptionId
