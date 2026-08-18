locals {
  trail_name = "${var.project_name}-trail"
  trail_arn  = "arn:${data.aws_partition.current.partition}:cloudtrail:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:trail/${local.trail_name}"
}

resource "aws_cloudtrail" "trail" {

  # checkov:skip=CKV_AWS_252:la notifica non passa da SNS su CloudTrail ma dalla pipeline EventBridge -> Lambda di questo progetto
  # checkov:skip=CKV_AWS_35:log cifrati con SSE-S3; CMK dedicata ha costo ricorrente
  # checkov:skip=CKV2_AWS_10:integrazione con CloudWatch Logs non necessaria: gli eventi arrivano gia' in tempo reale via EventBridge

  depends_on = [aws_s3_bucket_policy.trail_policy]

  name                          = local.trail_name
  s3_bucket_name                = aws_s3_bucket.logs.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
}

resource "aws_s3_bucket" "logs" {

  # checkov:skip=CKV_AWS_18:access logging richiederebbe un secondo bucket dedicato, costo>beneficio
  # checkov:skip=CKV_AWS_144:replica cross-region non necessaria in ambiente demo mono-regione
  # checkov:skip=CKV_AWS_145:cifratura SSE-S3 (AES256) attiva; CMK dedicata ha costo ricorrente
  # checkov:skip=CKV2_AWS_62:event notification non previste: nessun consumatore a valle

  bucket        = "${var.project_name}-trail-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "s3pba" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "aes256" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_iam_policy_document" "trail_policy" {
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.logs.arn]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
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
    resources = ["${aws_s3_bucket.logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "trail_policy" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.trail_policy.json
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "expire-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}