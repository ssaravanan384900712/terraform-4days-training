output "vpc_id" {
  description = "Imported VPC ID"
  value       = aws_vpc.imported.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.imported.cidr_block
}

output "vpc_default" {
  description = "Is this the default VPC?"
  value       = aws_vpc.imported.default
}
