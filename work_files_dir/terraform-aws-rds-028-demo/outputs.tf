output "db_endpoint" {
  description = "RDS Postgres endpoint (host:port)"
  value       = aws_db_instance.postgres.endpoint
}
output "db_host" {
  value = aws_db_instance.postgres.address
}
output "db_port" {
  value = aws_db_instance.postgres.port
}
output "db_name" {
  value = aws_db_instance.postgres.db_name
}
output "psql_connect" {
  description = "Run this to connect (you will be prompted for password)"
  value       = "psql -h ${aws_db_instance.postgres.address} -p ${aws_db_instance.postgres.port} -U robochef -d robochefdb"
}
