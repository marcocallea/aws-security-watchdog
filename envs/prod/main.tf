module "notify" {
  source       = "../../modules/notify"
  project_name = "aws-security-watchdog"
  alert_email  = var.alert_email
}

module "storage" {
  source       = "../../modules/storage"
  project_name = "aws-security-watchdog"
}

module "cloudtrail" {
  source       = "../../modules/cloudtrail"
  project_name = "aws-security-watchdog"
}

module "detection" {
  source        = "../../modules/detection"
  project_name  = "aws-security-watchdog"
  table_name    = module.storage.table_name
  table_arn     = module.storage.table_arn
  sns_topic_arn = module.notify.sns_topic_arn
}

module "api" {
  source       = "../../modules/api"
  project_name = "aws-security-watchdog"
  table_name   = module.storage.table_name
  table_arn    = module.storage.table_arn
}