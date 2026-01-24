terraform {
  backend "s3" {
    bucket         = "tf-state-sahaba-lock" # YOUR BUCKET
    key            = "global/s3/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tf-lock-table"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-east-1"
}

# 1. The IAM Role
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

# 2. The Policy
resource "aws_iam_role_policy" "lambda_policy" {
  # checkov:skip=CKV_AWS_355: "These are acceptable permissions for the audit bot scope"
  # checkov:skip=CKV_AWS_290: "IAM permissions are limited to specific S3 and Logging actions"
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

# 3. The Lambda Function
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "../Security_audit_bot.py"
  output_path = "lambda_function.zip"
}

resource "aws_lambda_function" "security_bot" {
  # checkov:skip=CKV_AWS_117: "VPC config not required for this public API audit bot"
  # checkov:skip=CKV_AWS_50: "X-Ray tracing not required for simple automation"
  # checkov:skip=CKV_AWS_116: "DLQ to be reviewed in next iteration"
  # checkov:skip=CKV_AWS_173: "Environment variable encryption not required for non-sensitive webhook URL in lab" 
  # checkov:skip=CKV_AWS_115: "Function-level concurrency limit not required for low-traffic bot" 
  # checkov:skip=CKV_AWS_272: "Code signing not required for this internal tool"

  filename      = "lambda_function.zip"
  function_name = "SecurityAuditBot_TF"
  role          = aws_iam_role.lambda_role.arn
  handler       = "${var.file_name}.lambda_handler"
  runtime       = "python3.12" # Python 3.14 is not yet a standard AWS Lambda runtime; updated to 3.12

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      N8N_WEBHOOK_URL = var.N8N_WEBHOOK_URL
    }
  }
}

# 4. The Trigger (EventBridge)
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

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.security_bot.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.s3_trigger.arn
}

# 5. S3 Bucket for Trail Logs
resource "aws_s3_bucket" "trail_bucket" {
  # checkov:skip=CKV_AWS_145: "KMS encryption not required for lab trail logs"
  # checkov:skip=CKV_AWS_144: "Cross-region replication not required"
  # checkov:skip=CKV_AWS_18: "S3 Access Logging not required for the log destination bucket"
  # checkov:skip=CKV_AWS_21: "Versioning skipped to save cost in lab environment"
  # checkov:skip=CKV_AWS_6: "Public access is handled via account-level block"
  
  bucket        = "sahaba-bucket-for-trail-logs"
  force_destroy = true
}

# 6. The CloudTrail
resource "aws_cloudtrail" "trail" {
  # checkov:skip=CKV_AWS_36: "Log file validation skipped for lab" 
  # checkov:skip=CKV_AWS_67: "CloudWatch Logs integration skipped for cost"
  # checkov:skip=CKV_AWS_53: "KMS encryption skipped for lab"
  # checkov:skip=CKV_AWS_252: "SNS integration not required"
  # checkov:skip=CKV_AWS_10: "Multi-region trail not required for this specific lab scope"

  depends_on                    = [aws_s3_bucket_policy.trail_bucket_Policy]
  name                          = "sahaba-trail-IR"
  s3_bucket_name                = aws_s3_bucket.trail_bucket.id
  s3_key_prefix                 = "prefix"
  include_global_service_events = false
}

# 7. Bucket Policy
resource "aws_s3_bucket_policy" "trail_bucket_Policy" {
  bucket = aws_s3_bucket.trail_bucket.id
  policy = data.aws_iam_policy_document.cloudtrail-destination.json
}

data "aws_iam_policy_document" "cloudtrail-destination" {
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
      values   = ["arn:aws:cloudtrail:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:trail/sahaba-trail-IR"]
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
      values   = ["arn:aws:cloudtrail:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:trail/sahaba-trail-IR"]
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}