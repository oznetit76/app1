provider "aws" {
  region = "us-east-1"
}

resource "aws_dynamodb_table" "restaurants" {
  name         = "Restaurants"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "style"

  attribute {
    name = "style"
    type = "S"
  }
}

resource "aws_dynamodb_table" "restaurants" {
  name         = "Restaurants"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "style"

  attribute {
    name = "style"
    type = "S"
  }
}

resource "aws_dynamodb_table_item" "pizza_hut" {
  table_name = aws_dynamodb_table.restaurants.name
  hash_key   = "style"

  item = <<EOT
  {
    "style": {"S": "Italian"},
    "name": {"S": "Pizza Hut"},
    "address": {"S": "wherever1"},
    "openHour": {"S": "09:00"},
    "closeHour": {"S": "23:00"},
    "vegetarian": {"BOOL": true}
  }
  EOT
}

resource "aws_dynamodb_table_item" "la_palapa" {
  table_name = aws_dynamodb_table.restaurants.name
  hash_key   = "style"

  item = <<EOT
  {
    "style": {"S": "Mexican"},
    "name": {"S": "La Palapa"},
    "address": {"S": "wherever2"},
    "openHour": {"S": "09:00"},
    "closeHour": {"S": "23:00"},
    "vegetarian": {"BOOL": false}
  }
  EOT
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy_attachment" "lambda_dynamodb" {
  name       = "lambda_dynamodb_attach"
  roles      = [aws_iam_role.lambda_exec.name]
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_lambda_function" "restaurant_api" {
  function_name    = "RestaurantAPI"
  role            = aws_iam_role.lambda_exec.arn
  runtime        = "python3.10"
  handler        = "lambda_function.lambda_handler"
  filename       = "lambda.zip"
  source_code_hash = filebase64sha256("lambda.zip")
  
  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.restaurants.name
    }
  }
}

resource "aws_apigatewayv2_api" "restaurant_api" {
  name          = "restaurant_api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "restaurant_stage" {
  api_id      = aws_apigatewayv2_api.restaurant_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.restaurant_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.restaurant_api.invoke_arn
}

resource "aws_apigatewayv2_route" "lambda_route" {
  api_id    = aws_apigatewayv2_api.restaurant_api.id
  route_key = "GET /restaurants"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_lambda_permission" "apigw_lambda" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.restaurant_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.restaurant_api.execution_arn}/*/*"
}

resource "aws_s3_bucket" "api_logs" {
  bucket = "restaurant-api-logs"
  force_destroy = false

  lifecycle {
    prevent_destroy = true
  }

  versioning {
    enabled = true
  }

  logging {
    target_bucket = aws_s3_bucket.api_logs.id
    target_prefix = "logs/"
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

resource "aws_iam_policy" "lambda_logging" {
  name        = "LambdaLoggingPolicy"
  description = "Allows Lambda to write logs to S3 securely"
  policy      = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["s3:PutObject"],
        Resource = ["${aws_s3_bucket.api_logs.arn}/*"],
        Condition = {
          "StringEquals": {
            "s3:x-amz-server-side-encryption": "AES256"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logging_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_logging.arn
}