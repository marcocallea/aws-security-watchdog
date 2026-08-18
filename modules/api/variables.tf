variable "project_name" {
  description = "Prefisso per i nomi delle risorse"
  type        = string
}

variable "table_name" {
  description = "Nome della tabella DynamoDB da interrogare"
  type        = string
}

variable "table_arn" {
  description = "ARN della tabella, per la policy IAM del reader"
  type        = string
}