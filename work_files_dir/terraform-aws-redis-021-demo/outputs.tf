output "redis_endpoint" {
  description = "Redis cluster endpoint address"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "redis_port" {
  value = aws_elasticache_cluster.redis.port
}

output "client_public_ip" {
  description = "EC2 client instance public IP"
  value       = aws_instance.redis_client.public_ip
}

output "ssh_command" {
  value = "ssh -i ${pathexpand(var.private_key_path)} ubuntu@${aws_instance.redis_client.public_ip}"
}

output "redis_cli_connect" {
  description = "Run this from inside the EC2 client"
  value       = "redis-cli -h ${aws_elasticache_cluster.redis.cache_nodes[0].address} -p ${aws_elasticache_cluster.redis.port}"
}
