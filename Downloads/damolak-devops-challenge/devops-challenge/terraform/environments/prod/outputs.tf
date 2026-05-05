output "app_url"         { value = "http://${module.ecs.alb_dns_name}" }
output "ecr_repo_url"    { value = module.ecr.repository_url }
output "cluster_name"    { value = module.ecs.cluster_name }
output "service_name"    { value = module.ecs.service_name }
output "log_group_name"  { value = module.ecs.log_group_name }
output "dashboard_name"  { value = module.monitoring.dashboard_name }
output "aws_account_id"  { value = data.aws_caller_identity.current.account_id }
