provider "aws" {
  region = "us-east-1" # Or your region
}

# 1. The IAM Role (The Identity)
# We need a role that allows Lambda to run.
resource "aws_iam_role" "lambda_role" {
  name = "security_bot_role_tf"

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

# 2. The Policy (The Permission Slip)
# You need to translate your manual permissions (S3, Logs, SNS) into this block.
resource "aws_iam_role_policy" "lambda_policy" {
  name = "security_bot_policy_tf"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetBucketVersioning",
          "s3:PutBucketVersioning",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

# 3. The Lambda Function (The Brain)
# This zips your python code and uploads it.
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "../Security-audit-bot.py" # Point to your Python file
  output_path = "lambda_function.zip"
}

resource "aws_lambda_function" "security_bot" {
  filename      = "lambda_function.zip"
  function_name = "SecurityAuditBot_TF"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.14"

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      # Remember the variable we set in the console? Put it here.
      N8N_WEBHOOK_URL = var.N8N_WEBHOOK_URL
    }
  }
}

# 4. The Trigger (EventBridge)
# This is the hardest part. You need a Rule and a Permission.
resource "aws_cloudwatch_event_rule" "s3_trigger" {
  name        = "capture_s3_creation"
  description = "Trigger Lambda when S3 bucket is created"

  event_pattern = jsonencode({
    "source": ["aws.s3"],
    "detail-type": ["AWS API Call via CloudTrail"],
    "detail": {
      "eventSource": ["s3.amazonaws.com"],
      "eventName": ["CreateBucket"]
    }
  })
}

resource "aws_cloudwatch_event_target" "sns" {
  rule      = aws_cloudwatch_event_rule.s3_trigger.name
  target_id = "SendToLambda"
  arn       = aws_lambda_function.security_bot.arn
}

# ALLOW EventBridge to call Lambda (Critical Step often missed)
resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.security_bot.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.s3_trigger.arn
}