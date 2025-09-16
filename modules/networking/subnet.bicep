/*
Subnet Management Module
Creates or updates a subnet within an existing Virtual Network.

Features:
- Idempotent subnet creation/update
- Support for subnet delegations (e.g., Container Apps, Functions)
- Flexible address prefix configuration
*/

@description('Name of the virtual network')
param vnetName string

@description('Name of the subnet')
param subnetName string

@description('Address prefix for the subnet (CIDR notation)')
param addressPrefix string

@description('Array of subnet delegations for specific Azure services')
param delegations array = []

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  name: '${vnetName}/${subnetName}'
  properties: {
    addressPrefix: addressPrefix
    delegations: delegations
  }
}

output subnetId string = subnet.id
output subnetName string = subnetName
