import azure.functions as func
import azure.cosmos.cosmos_client as cosmos_client
import json
import os

app = func.FunctionApp()

@app.route(route="HttpTrigger", auth_level=func.AuthLevel.ANONYMOUS)
def HttpTrigger(req: func.HttpRequest) -> func.HttpResponse:

    # Connect to Cosmos DB using connection string from environment variables
    CONNECTION_STRING = os.environ["COSMOS_CONNECTION_STRING"]
    DATABASE_NAME = "crc-database"
    CONTAINER_NAME = "counter"

    # Initialise the Cosmos client
    client = cosmos_client.CosmosClient.from_connection_string(CONNECTION_STRING)
    database = client.get_database_client(DATABASE_NAME)
    container = database.get_container_client(CONTAINER_NAME)

    # Read the counter document
    counter_doc = container.read_item(item="counter", partition_key="counter")

    # Increment the count
    counter_doc["count"] += 1

    # Write the updated document back to Cosmos DB
    container.replace_item(item="counter", body=counter_doc)

    # Return the new count as JSON
    return func.HttpResponse(
        body=json.dumps({"count": counter_doc["count"]}),
        status_code=200,
        mimetype="application/json",
        headers={"Access-Control-Allow-Origin": "*"}
    )