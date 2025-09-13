/*
Virtual Network Orchestrator Module
Provides a unified interface for VNet management - creates new or configures existing VNets.

This module acts as a facade that:
- Routes to new VNet creation or existing VNet configuration based on parameters
- Provides consistent outputs regardless of which path is taken
- Simplifies VNet management for consuming templates
*/

@description('Azure region for the deployment')
param location string

@description('The name of the virtual network')
param vnetName string

@description('Create new VNet (false) or configure existing VNet (true)')
param useExistingVnet bool = false

@description('Subscription ID of existing VNet (if different from current)')
param existingVnetSubscriptionId string = subscription().subscriptionId

@description('Resource Group of existing VNet (if different from current)')
param existingVnetResourceGroupName string = resourceGroup().name

@description('Name of AI Services agent subnet')
param agentSubnetName string = 'agent-subnet'

@description('Name of Private Endpoint subnet')
param peSubnetName string = 'pe-subnet'

@description('Name of Container Apps infrastructure subnet')
param acaSubnetName string = 'aca-subnet'

@description('Address space for new VNet (ignored if using existing)')
param vnetAddressPrefix string = ''

@description('Address prefix for agent subnet')
param agentSubnetPrefix string = ''

@description('Address prefix for ACA subnet')
param acaSubnetPrefix string = ''

@description('Address prefix for private endpoint subnet')
param peSubnetPrefix string = ''

// Create new VNet with all subnets
module newVNet 'vnet.bicep' = if (!useExistingVnet) {
  name: 'vnet-deployment'
  params: {
    location: location
    vnetName: vnetName
    agentSubnetName: agentSubnetName
    acaSubnetName: acaSubnetName
    peSubnetName: peSubnetName
    vnetAddressPrefix: vnetAddressPrefix
    agentSubnetPrefix: agentSubnetPrefix
    acaSubnetPrefix: acaSubnetPrefix
    peSubnetPrefix: peSubnetPrefix
  }
}

// Configure existing VNet with required subnets
module existingVNet 'vnet-subnets.bicep' = if (useExistingVnet) {
  name: 'vnet-subnets-deployment'
  params: {
    vnetName: vnetName
    vnetResourceGroupName: existingVnetResourceGroupName
    vnetSubscriptionId: existingVnetSubscriptionId
    agentSubnetName: agentSubnetName
    acaSubnetName: acaSubnetName
    peSubnetName: peSubnetName
    agentSubnetPrefix: agentSubnetPrefix
    acaSubnetPrefix: acaSubnetPrefix
    peSubnetPrefix: peSubnetPrefix
  }
}

// Unified outputs - works for both new and existing VNet scenarios
output virtualNetworkName string = useExistingVnet ? existingVNet!.outputs.virtualNetworkName : newVNet!.outputs.virtualNetworkName
output virtualNetworkId string = useExistingVnet ? existingVNet!.outputs.virtualNetworkId : newVNet!.outputs.virtualNetworkId
output virtualNetworkSubscriptionId string = useExistingVnet ? existingVNet!.outputs.virtualNetworkSubscriptionId : newVNet!.outputs.virtualNetworkSubscriptionId
output virtualNetworkResourceGroup string = useExistingVnet ? existingVNet!.outputs.virtualNetworkResourceGroup : newVNet!.outputs.virtualNetworkResourceGroup

output agentSubnetName string = agentSubnetName
output agentSubnetId string = useExistingVnet ? existingVNet!.outputs.agentSubnetId : newVNet!.outputs.agentSubnetId

output acaSubnetName string = useExistingVnet ? existingVNet!.outputs.acaSubnetName : newVNet!.outputs.acaSubnetName
output acaSubnetId string = useExistingVnet ? existingVNet!.outputs.acaSubnetId : newVNet!.outputs.acaSubnetId

output peSubnetName string = peSubnetName
output peSubnetId string = useExistingVnet ? existingVNet!.outputs.peSubnetId : newVNet!.outputs.peSubnetId
