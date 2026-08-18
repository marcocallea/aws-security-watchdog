data "archive_file" "reader" {
  type        = "zip"
  source_dir  = "${path.module}/../../src/reader"
  output_path = "${path.module}/build/reader.zip"
}

resource "aws_iam_role" "reader" {
  name = "${var.project_name}-reader-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "reader_logs" {
  role       = aws_iam_role.reader.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "reader" {
  name = "${var.project_name}-reader-policy"
  role = aws_iam_role.reader.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:Query"]
      Resource = [var.table_arn]
    }]
  })
}

resource "aws_cloudwatch_log_group" "reader" {

  # checkov:skip=CKV_AWS_338:retention 14 giorni scelta di costo per ambiente demo
  # checkov:skip=CKV_AWS_158:log cifrati con chiave gestita da AWS; CMK dedicata ha costo ricorrente

  name              = "/aws/lambda/${var.project_name}-reader"
  retention_in_days = 14
}

resource "aws_lambda_function" "reader" {

  # checkov:skip=CKV_AWS_50:X-Ray non abilitato: costo per traccia, osservabilita' affidata ai log CloudWatch
  # checkov:skip=CKV_AWS_117:la funzione non accede a risorse private; una VPC aggiungerebbe cold start e un NAT senza benefici
  # checkov:skip=CKV_AWS_116:nessuna DLQ: invocazione sincrona da API Gateway, l'errore torna al chiamante
  # checkov:skip=CKV_AWS_173:le variabili contengono solo il nome della tabella, nessun dato sensibile
  # checkov:skip=CKV_AWS_272:code signing richiede AWS Signer, fuori scope per un progetto demo
  # checkov:skip=CKV_AWS_115:nessun limite di concorrenza: traffico previsto minimo, budget alert a protezione

  function_name    = "${var.project_name}-reader"
  role             = aws_iam_role.reader.arn
  filename         = data.archive_file.reader.output_path
  source_code_hash = data.archive_file.reader.output_base64sha256
  handler          = "handler.handler"
  runtime          = "python3.13"
  timeout          = 10
  memory_size      = 256

  environment {
    variables = {
      TABLE_NAME = var.table_name
    }
  }

  depends_on = [aws_cloudwatch_log_group.reader]
}

resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "reader" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.reader.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "events" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "GET /events"
  target             = "integrations/${aws_apigatewayv2_integration.reader.id}"
  authorization_type = "AWS_IAM"
}

resource "aws_apigatewayv2_stage" "default" {

  # checkov:skip=CKV_AWS_76:access logging richiede un log group dedicato e costo aggiuntivo

  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "api" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.reader.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}