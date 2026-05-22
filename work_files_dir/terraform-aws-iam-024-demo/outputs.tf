output "user_arn" { value = aws_iam_user.demo.arn }
output "group_name" { value = aws_iam_group.demo.name }
output "custom_policy_arn" { value = aws_iam_policy.s3_read.arn }
output "role_arn" { value = aws_iam_role.ec2_role.arn }
output "instance_profile_name" { value = aws_iam_instance_profile.ec2.name }
