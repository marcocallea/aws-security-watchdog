# 1. Login alla console
resource "aws_cloudwatch_event_rule" "console_login" {
  name        = "${var.project_name}-console-login"
  description = "Login alla console AWS"

  event_pattern = jsonencode({
    source        = ["aws.signin"]
    "detail-type" = ["AWS Console Sign In via CloudTrail"]
  })
}

# 2. Security group aperti o modificati
resource "aws_cloudwatch_event_rule" "sg_changes" {
  name        = "${var.project_name}-sg-changes"
  description = "Modifiche alle regole dei security group"

  event_pattern = jsonencode({
    source        = ["aws.ec2"]
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = [
        "AuthorizeSecurityGroupIngress",
        "AuthorizeSecurityGroupEgress",
        "RevokeSecurityGroupIngress",
      ]
    }
  })
}

# 3. Movimenti IAM: creazione utenti, chiavi, policy
resource "aws_cloudwatch_event_rule" "iam_changes" {
  name        = "${var.project_name}-iam-changes"
  description = "Creazione di utenti, chiavi di accesso e attacco di policy"

  event_pattern = jsonencode({
    source        = ["aws.iam"]
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = [
        "CreateUser",
        "CreateAccessKey",
        "AttachUserPolicy",
        "AttachRolePolicy",
        "PutUserPolicy",
        "DeleteUser",
      ]
    }
  })
}

# 4. Qualcuno spegne la sorveglianza
resource "aws_cloudwatch_event_rule" "trail_tampering" {
  name        = "${var.project_name}-trail-tampering"
  description = "Disattivazione o cancellazione di CloudTrail"

  event_pattern = jsonencode({
    source        = ["aws.cloudtrail"]
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = ["StopLogging", "DeleteTrail", "UpdateTrail"]
    }
  })
}

data "archive_file" "detector" {
  type        = "zip"
  source_dir  = "${path.module}/../../src/detector"
  output_path = "${path.module}/build/detector.zip"
}

resource "aws_iam_role" "detector" {
  name = "${var.project_name}-detector-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "detector_logs" {
  role       = aws_iam_role.detector.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "detector" {

  # checkov:skip=CKV_AWS_290:kms:GenerateDataKey su Resource * e' necessario per pubblicare su un topic cifrato con chiave gestita da AWS (alias/aws/sns), il cui ARN non e' referenziabile staticamente; l'accesso e' comunque vincolato dalla key policy della chiave
  # checkov:skip=CKV_AWS_355:vedi CKV_AWS_290, stessa motivazione

  name = "${var.project_name}-detector-policy"
  role = aws_iam_role.detector.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = [var.table_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = [var.sns_topic_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource = ["*"]
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "detector" {

  # checkov:skip=CKV_AWS_338:retention 14 giorni scelta di costo per ambiente demo
  # checkov:skip=CKV_AWS_158:log cifrati con chiave gestita da AWS; CMK dedicata ha costo ricorrente

  name              = "/aws/lambda/${var.project_name}-detector"
  retention_in_days = 14
}

resource "aws_lambda_function" "detector" {

  # checkov:skip=CKV_AWS_50:X-Ray non abilitato: costo per traccia, osservabilita' affidata ai log CloudWatch
  # checkov:skip=CKV_AWS_117:la funzione non accede a risorse private; una VPC aggiungerebbe cold start e un NAT senza benefici
  # checkov:skip=CKV_AWS_116:nessuna DLQ: EventBridge ritenta automaticamente le invocazioni fallite; DLQ in roadmap
  # checkov:skip=CKV_AWS_173:le variabili contengono nome tabella e ARN del topic, nessun segreto
  # checkov:skip=CKV_AWS_272:code signing richiede AWS Signer, fuori scope per un progetto demo
  # checkov:skip=CKV_AWS_115:nessun limite di concorrenza: volume di eventi minimo, budget alert a protezione

  function_name    = "${var.project_name}-detector"
  role             = aws_iam_role.detector.arn
  filename         = data.archive_file.detector.output_path
  source_code_hash = data.archive_file.detector.output_base64sha256
  handler          = "handler.handler"
  runtime          = "python3.13"
  timeout          = 15
  memory_size      = 256

  environment {
    variables = {
      TABLE_NAME = var.table_name
      TOPIC_ARN  = var.sns_topic_arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.detector]
}

locals {
  rules = {
    console_login   = aws_cloudwatch_event_rule.console_login
    sg_changes      = aws_cloudwatch_event_rule.sg_changes
    iam_changes     = aws_cloudwatch_event_rule.iam_changes
    trail_tampering = aws_cloudwatch_event_rule.trail_tampering
  }
}

resource "aws_cloudwatch_event_target" "detector" {
  for_each = local.rules

  rule      = each.value.name
  target_id = "detector"
  arn       = aws_lambda_function.detector.arn
}

resource "aws_lambda_permission" "eventbridge" {
  for_each = local.rules

  statement_id  = "AllowExecutionFrom-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.detector.function_name
  principal     = "events.amazonaws.com"
  source_arn    = each.value.arn
}