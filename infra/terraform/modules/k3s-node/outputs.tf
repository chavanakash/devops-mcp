output "instance_id" {
  value = aws_instance.node.id
}

output "public_ip" {
  value = aws_eip.node.public_ip
}

output "public_dns" {
  description = "AWS-assigned public DNS name for the EIP — CloudFront custom origins reject raw IP addresses as domain_name, so this is what static-site's /api/* proxy uses instead."
  value       = aws_eip.node.public_dns
}

output "status_api_url" {
  value = "http://${aws_eip.node.public_ip}:${var.status_api_nodeport}"
}
