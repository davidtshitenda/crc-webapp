const { app } = require('@azure/functions');
const { CosmosClient } = require('@azure/cosmos');

const client = new CosmosClient(process.env.COSMOS_CONNECTION_STRING);
const database = client.database('crc-database');
const container = database.container('counter');

app.http('HttpTrigger', {
    methods: ['GET', 'POST'],
    authLevel: 'anonymous',
    handler: async (request, context) => {

        // Read the counter document
        const { resource: counterDoc } = await container
            .item('counter', 'counter')
            .read();

        // Increment the count
        counterDoc.count += 1;

        // Write the updated count back to Cosmos DB
        await container
            .item('counter', 'counter')
            .replace(counterDoc);

        // Return the new count as JSON
        return {
            status: 200,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            body: JSON.stringify({ count: counterDoc.count })
        };
    }
});