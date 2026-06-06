// ============================================================
// Cloud Resume Challenge — Infrastructure as Code
// Bicep template defining all Azure resources for the CRC
// Author: David T. Wa Tshitenda
// ============================================================
// Deploy with:
// az deployment group create \
//   --resource-group crc-staticwebapp \
//   --template-file main.bicep \
//   --parameters cosmosAccountName='crc-prj-cosmosdb'
// ============================================================

// ── PARAMETERS ──────────────────────────────────────────────
// Parameters are inputs you can change at deploy time
// without editing the template itself

@description('Azure region for all resources')
param location string = 'southafricanorth'

@description('Name of the storage account for static website')
param storageAccountName string = 'crcstorageaccountprj'

@description('Name of the Cosmos DB account')
param cosmosAccountName string = 'crc-prj-cosmosdb'

@description('Name of the Cosmos DB database')
param cosmosDatabaseName string = 'crc-database'

@description('Name of the Cosmos DB container')
param cosmosContainerName string = 'counter'

@description('Name of the Python Function App')
param functionAppName string = 'crc-counter-api-python'

@description('Name of the App Service Plan for the Function App')
param appServicePlanName string = 'crc-consumption-plan'

@description('Name of the storage account used by the Function App runtime')
param functionStorageAccountName string = 'crcfunctionstorage'

// ── STORAGE ACCOUNT (Static Website) ────────────────────────
// This is the storage account that hosts your HTML resume
// Static website hosting is enabled via the portal separately
// (Bicep does not directly enable static website hosting —
// it requires a deployment script or manual portal step)

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'   // Locally Redundant Storage — cheapest, fine for portfolio
  }
  kind: 'StorageV2'         // General purpose v2 — required for static website
  properties: {
    allowBlobPublicAccess: true   // Required for static website public access
    minimumTlsVersion: 'TLS1_2'  // Security best practice
    supportsHttpsTrafficOnly: true
  }
}

// ── STORAGE ACCOUNT (Function App Runtime) ──────────────────
// Azure Functions requires a separate storage account for its
// internal operations (storing function code, triggers, logs)
// This is different from the static website storage account

resource functionStorageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: functionStorageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

// ── COSMOS DB ACCOUNT ────────────────────────────────────────
// The NoSQL database account — top level of the hierarchy
// Account → Database → Container → Documents

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-11-15' = {
  name: cosmosAccountName
  location: location
  kind: 'GlobalDocumentDB'    // Standard Cosmos DB for NoSQL API
  properties: {
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'  // Standard consistency — reads your own writes
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0   // Primary region
        isZoneRedundant: false
      }
    ]
    databaseAccountOfferType: 'Standard'
    enableAutomaticFailover: false
    capabilities: [
      {
        name: 'EnableServerless'  // Serverless mode — pay per request, not per hour
      }
    ]
  }
}

// ── COSMOS DB DATABASE ───────────────────────────────────────
// The database inside the account — second level of hierarchy

resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-11-15' = {
  parent: cosmosAccount    // Belongs to the account defined above
  name: cosmosDatabaseName
  properties: {
    resource: {
      id: cosmosDatabaseName
    }
  }
}

// ── COSMOS DB CONTAINER ──────────────────────────────────────
// The container inside the database — third level of hierarchy
// This is where your counter document lives

resource cosmosContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-11-15' = {
  parent: cosmosDatabase   // Belongs to the database defined above
  name: cosmosContainerName
  properties: {
    resource: {
      id: cosmosContainerName
      partitionKey: {
        paths: [
          '/id'            // Partition key — same as what you set manually in the portal
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        includedPaths: [
          {
            path: '/*'     // Index all fields
          }
        ]
      }
    }
  }
}

// ── APP SERVICE PLAN (Consumption) ──────────────────────────
// Defines the hosting plan for the Function App
// Consumption plan = serverless, pay per execution
// Y1 is the SKU name for the Consumption plan

resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: 'Y1'           // Y1 = Consumption plan (serverless)
    tier: 'Dynamic'      // Dynamic = scales to zero when not in use
  }
  kind: 'linux'          // Linux for Python Functions
  properties: {
    reserved: true       // Required for Linux — marks it as Linux-based
  }
}

// ── FUNCTION APP ─────────────────────────────────────────────
// The serverless Function App that runs your Python counter code
// Depends on: App Service Plan + Function Storage Account + Cosmos DB

resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'   // Linux Function App
  properties: {
    serverFarmId: appServicePlan.id   // Links to the Consumption plan above
    siteConfig: {
      linuxFxVersion: 'Python|3.12'   // Python 3.12 runtime
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          // References the function storage account connection string
          value: 'DefaultEndpointsProtocol=https;AccountName=${functionStorageAccount.name};AccountKey=${functionStorageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'        // Functions runtime v4
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'    // Python runtime
        }
        {
          name: 'COSMOS_CONNECTION_STRING'
          // Dynamically retrieves the Cosmos DB connection string at deploy time
          // No hardcoding credentials in the template
          value: cosmosAccount.listConnectionStrings().connectionStrings[0].connectionString
        }
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'      // Tells Azure to run pip install during deployment
        }
      ]
      ftpsState: 'Disabled'           // Security best practice — disable FTP
      minTlsVersion: '1.2'
    }
    httpsOnly: true                   // Force HTTPS
  }
}

// ── OUTPUTS ──────────────────────────────────────────────────
// Outputs are values that Azure prints after deployment
// Useful for confirming what was created and getting URLs

output storageAccountName string = storageAccount.name
output cosmosAccountName string = cosmosAccount.name
output functionAppName string = functionApp.name
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}/api/HttpTrigger'
output cosmosEndpoint string = cosmosAccount.properties.documentEndpoint
