import json
import boto3
from datetime import datetime

# Ensure AWS region is specified to avoid NoRegionError
dynamodb = boto3.resource('dynamodb', region_name='us-east-1')
table = dynamodb.Table('Restaurants')

def lambda_handler(event, context):
    try:
        params = event.get('queryStringParameters', {})
        
        # Extract query parameters
        style = params.get('style')
        vegetarian = params.get('vegetarian')
        now = datetime.utcnow().strftime('%H:%M')
        
        if not style:
            return {"statusCode": 400, "body": json.dumps({"message": "Missing required parameter: style"})}
        
        if vegetarian not in ['true', 'false', None]:
            return {"statusCode": 400, "body": json.dumps({"message": "Invalid value for parameter: vegetarian. Use 'true' or 'false'."})}
        
        ### Build query parameters ###
        
        # This dictionary maps placeholders (prefixed with :) to actual values used in the query.
        expression_values = {":style": style, ":now": now}
        
        # This dictionary avoids conflicts with DynamoDB reserved keywords.
        expression_names = {"#style": "style", "#openHour": "openHour", "#closeHour": "closeHour"}
        
        # List that holds filter conditions for the query
        filter_conditions = ["#openHour <= :now", "#closeHour >= :now"]
        
        if vegetarian:
            expression_values[":vegetarian"] = vegetarian.lower() == 'true'
            expression_names["#vegetarian"] = "vegetarian"
            filter_conditions.append("#vegetarian = :vegetarian")
        
        # Construct filter expression
        filter_expression = " AND ".join(filter_conditions)
        
        # Querying DynamoDB (Query instead of Scan)
        response = table.query(
            KeyConditionExpression="#style = :style",
            FilterExpression=filter_expression,
            ExpressionAttributeValues=expression_values,
            ExpressionAttributeNames=expression_names
        )
        
        restaurants = response.get('Items', [])
        
        if not restaurants:
            return {"statusCode": 404, "body": json.dumps({"message": "No matching restaurant found"})}
        
        recommendation = restaurants[0]  # Return the first match
        return {
            "statusCode": 200,
            "body": json.dumps({"restaurantRecommendation": recommendation})
        }
    
    except Exception as e:
        return {
            "statusCode": 500,
            "body": json.dumps({"message": "Internal server error", "error": str(e)})
        }
