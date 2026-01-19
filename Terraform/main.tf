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
  source_file = "../Security_audit_bot.py" # Point to your Python file
  output_path = "lambda_function.zip"
}

resource "aws_lambda_function" "security_bot" {
  filename      = "lambda_function.zip"
  function_name = "SecurityAuditBot_TF"
  role          = aws_iam_role.lambda_role.arn
  handler       = "${var.file_name}.lambda_handler"
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
  depends_on = [ aws_lambda_function.security_bot ]
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

# 5. create an s3 bucket
resource "aws_s3_bucket" "trail_bucket" {
  bucket        = "sahaba-bucket-for-trail-logs"
  force_destroy = true
}

# 6. Create the Trail
resource "aws_cloudtrail" "trail" {
  depends_on = [aws_s3_bucket_policy.trail_bucket_Policy]
  name                          = "sahaba-trail-IR"
  s3_bucket_name                = aws_s3_bucket.trail_bucket.id
  s3_key_prefix                 = "prefix"
  include_global_service_events = false
}

# 7. define bucket policy
# This will allow cloudtrail to upload data on s3
data "aws_iam_policy_document" "cloudtrail-destination" {
  depends_on = [ aws_s3_bucket.trail_bucket ]
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.trail_bucket.arn]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudtrail:us-east-1:${data.aws_caller_identity.current.account_id}:trail/sahaba-trail-IR"]
    }
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.trail_bucket.arn}/prefix/AWSLogs/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudtrail:us-east-1:${data.aws_caller_identity.current.account_id}:trail/sahaba-trail-IR"]
    }
  }
}

resource "aws_s3_bucket_policy" "trail_bucket_Policy" {
  bucket = aws_s3_bucket.trail_bucket.id
  policy = data.aws_iam_policy_document.cloudtrail-destination.json
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}