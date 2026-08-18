resource "aws_dynamodb_table" "events" {

  # checkov:skip=CKV_AWS_119:cifratura at rest con chiave gestita da AWS; CMK dedicata non giustificata in demo

  name         = "${var.project_name}-security-events"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "event_date"
  range_key    = "occurred_at"

  attribute {
    name = "event_date"
    type = "S"
  }

  attribute {
    name = "occurred_at"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }


  tags = {
    Name = "${var.project_name}-events"
  }
}