/*
New Virtual Network Module
This module creates a new VNet with all required subnets for AI agent infrastructure:

Subnets Created:
- Agent subnet (AI Services network injection with delegation)
- ACA subnet (Container Apps Environment infrastructure)
- Private Endpoint subnet (secure connectivity)

Address Space Management:
- Supports custom CIDR blocks or sensible defaults
- Automatic subnet calculation based on VNet prefix
- Deterministic addressing for production deployments
*/

@description('Azure region for the deployment')
param location string

@description('The name of the virtual network')
param vnetName string = 'ai-agent-vnet'

@description('The name of AI Services agent subnet')
param agentSubnetName string = 'agent-subnet'

@description('The name of the Container Apps infrastructure subnet')
param acaSubnetName string = 'aca-subnet'

@description('The name of Private Endpoint subnet')
param peSubnetName string = 'pe-subnet'

@description('Address space for the VNet')
param vnetAddressPrefix string = ''

@description('Address prefix for the agent subnet')
param agentSubnetPrefix string = ''

@description('Address prefix for the ACA subnet (infrastructure subnet for Container Apps)')
param acaSubnetPrefix string = ''

@description('Address prefix for the private endpoint subnet')
param peSubnetPrefix string = ''

// Default to an available private network range if not specified
// 172.25.0.0/16 is available and avoids conflicts with existing VNets in subscription
var defaultVnetAddressPrefix = '172.25.0.0/16'
var vnetAddress = empty(vnetAddressPrefix) ? defaultVnetAddressPrefix : vnetAddressPrefix

// Calculate subnet addresses automatically if not provided
// Uses cidrSubnet(prefix, newBits, netNum) where newBits are added to existing prefix length
// For /16 VNet: 8 newBits = /24 subnet, 7 newBits = /23 subnet
// Example with 172.25.0.0/16: agent=172.25.0.0/24, pe=172.25.1.0/24, aca=172.25.2.0/23
var agentSubnet = empty(agentSubnetPrefix) ? cidrSubnet(vnetAddress, 8, 0) : agentSubnetPrefix  // /24 at .0.0
var peSubnet = empty(peSubnetPrefix) ? cidrSubnet(vnetAddress, 8, 1) : peSubnetPrefix          // /24 at .1.0  
var acaSubnet = empty(acaSubnetPrefix) ? cidrSubnet(vnetAddress, 7, 1) : acaSubnetPrefix       // /23 at .2.0-.3.255

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddress
      ]
    }
    subnets: [
      {
        name: agentSubnetName
        properties: {
          addressPrefix: agentSubnet
          // Agent subnet for AI Services - delegation required for capability host
          delegations: [
            {
              name: 'Microsoft.App_environments'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: acaSubnetName
        properties: {
          addressPrefix: acaSubnet
          // Container Apps Environment subnet - no delegation needed for Consumption plan
        }
      }
      {
        name: peSubnetName
        properties: {
          addressPrefix: peSubnet
          // Private Endpoints subnet - no delegation needed
        }
      }
    ]
  }
}

// Outputs
output virtualNetworkName string = virtualNetwork.name
output virtualNetworkId string = virtualNetwork.id
output virtualNetworkResourceGroup string = resourceGroup().name
output virtualNetworkSubscriptionId string = subscription().subscriptionId

output agentSubnetName string = agentSubnetName
output agentSubnetId string = '${virtualNetwork.id}/subnets/${agentSubnetName}'

output acaSubnetName string = acaSubnetName
output acaSubnetId string = '${virtualNetwork.id}/subnets/${acaSubnetName}'

output peSubnetName string = peSubnetName
output peSubnetId string = '${virtualNetwork.id}/subnets/${peSubnetName}'
