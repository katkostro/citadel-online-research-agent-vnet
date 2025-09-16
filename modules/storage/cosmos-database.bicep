// Creates the enterprise_memory database in Cosmos DB for AI Agents capability host
@description('Name of the Cosmos DB account')
param cosmosAccountName string

@description('Name of the database to create')
param databaseName string = 'enterprise_memory'

@description('Throughput for the database (RU/s)')
param throughput int = 400

@description('Project ID for AI Agents capability host containers')
param projectId string

// Format the project ID as a proper GUID with hyphens (capability host expects this format)
// Convert from: 1d66d510af2e44029cdb0e187496132f 
// To:         1d66d510-af2e-4402-9cdb-0e187496132f
var formattedProjectId = '${substring(projectId, 0, 8)}-${substring(projectId, 8, 4)}-${substring(projectId, 12, 4)}-${substring(projectId, 16, 4)}-${substring(projectId, 20, 12)}'

// Reference the existing Cosmos DB account
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' existing = {
  name: cosmosAccountName
}

// Create the enterprise_memory database
resource enterpriseMemoryDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  name: databaseName
  parent: cosmosAccount
  properties: {
    resource: {
      id: databaseName
    }
    options: {
      throughput: throughput
    }
  }
}

// Create required containers for AI Agents capability host
resource systemThreadMessageStoreContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  name: '${formattedProjectId}-system-thread-message-store'
  parent: enterpriseMemoryDatabase
  properties: {
    resource: {
      id: '${formattedProjectId}-system-thread-message-store'
      partitionKey: {
        paths: ['/id']
        kind: 'Hash'
      }
    }
  }
}

resource agentEntityStoreContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  name: '${formattedProjectId}-agent-entity-store'
  parent: enterpriseMemoryDatabase
  properties: {
    resource: {
      id: '${formattedProjectId}-agent-entity-store'
      partitionKey: {
        paths: ['/id']
        kind: 'Hash'
      }
    }
  }
}

resource threadMessageStoreContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  name: '${formattedProjectId}-thread-message-store'
  parent: enterpriseMemoryDatabase
  properties: {
    resource: {
      id: '${formattedProjectId}-thread-message-store'
      partitionKey: {
        paths: ['/id']
        kind: 'Hash'
      }
    }
  }
}

// Output the database name for reference
output databaseName string = enterpriseMemoryDatabase.name
output databaseResourceId string = enterpriseMemoryDatabase.id
