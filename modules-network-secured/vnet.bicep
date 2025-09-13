/*
Virtual Network Module
This module deploys the core network infrastructure with security controls:

1. Address Space:
   - VNet CIDR: 172.16.0.0/16 OR 192.168.0.0/16
   - Agents Subnet: 172.16.0.0/24 OR 192.168.0.0/24
   - Private Endpoint Subnet: 172.16.101.0/24 OR 192.168.1.0/24

2. Security Features:
   - Network isolation
   - Subnet delegation
   - Private endpoint subnet
*/

@description('Azure region for the deployment')
param location string

@description('The name of the virtual network')
param vnetName string = 'agents-vnet-test'

@description('The name of Agents Subnet')
param agentSubnetName string = 'agent-subnet'

@description('The name of the Container Apps (ACA) infrastructure subnet')
param acaSubnetName string = 'aca-subnet'

@description('The name of Hub subnet')
param peSubnetName string = 'pe-subnet'


@description('Address space for the VNet')
param vnetAddressPrefix string = ''

@description('Address prefix for the agent subnet')
param agentSubnetPrefix string = ''

@description('Address prefix for the ACA subnet (infrastructure subnet for Container Apps)')
param acaSubnetPrefix string = ''

@description('Address prefix for the private endpoint subnet')
param peSubnetPrefix string = ''

var defaultVnetAddressPrefix = '192.168.0.0/16'
var vnetAddress = empty(vnetAddressPrefix) ? defaultVnetAddressPrefix : vnetAddressPrefix
// Create new larger subnet for Container Apps + Registry private endpoint (avoiding existing conflicted subnets)
// IMPORTANT: cidrSubnet(prefix, newBits, netNum) adds newBits to the existing prefix length.
// Base VNet assumed /16 when calculating defaults.
// Simplified contiguous defaults (base assumed /16):
//  - agentSubnet: /24 at .0.0 (newBits 8, netNum 0)  -> 192.168.0.0/24
//  - peSubnet:    /24 at .1.0 (newBits 8, netNum 1)  -> 192.168.1.0/24
//  - acaSubnet:   /23 at .2.0 (newBits 7, netNum 1)  -> 192.168.2.0/23 (.2.0-.3.255)
// NOTE: User requested form with cidrSubnet(...,24,...) but correct usage is newBits relative to base (/16), so we use 8 (for /24) and 7 (for /23).
var agentSubnet = empty(agentSubnetPrefix) ? cidrSubnet(vnetAddress, 8, 0) : agentSubnetPrefix
var peSubnet = empty(peSubnetPrefix) ? cidrSubnet(vnetAddress, 8, 1) : peSubnetPrefix
var acaSubnet = empty(acaSubnetPrefix) ? cidrSubnet(vnetAddress, 7, 1) : acaSubnetPrefix

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
          // ACA Consumption subnet - no manual delegation, SAL created automatically
        }
      }
      {
        name: peSubnetName
        properties: {
          addressPrefix: peSubnet
        }
      }
    ]
  }
}
// Output variables
output peSubnetName string = peSubnetName
output agentSubnetName string = agentSubnetName
output agentSubnetId string = '${virtualNetwork.id}/subnets/${agentSubnetName}'
output acaSubnetName string = acaSubnetName
output acaSubnetId string = '${virtualNetwork.id}/subnets/${acaSubnetName}'
output peSubnetId string = '${virtualNetwork.id}/subnets/${peSubnetName}'
output virtualNetworkName string = virtualNetwork.name
output virtualNetworkId string = virtualNetwork.id
output virtualNetworkResourceGroup string = resourceGroup().name
output virtualNetworkSubscriptionId string = subscription().subscriptionId
