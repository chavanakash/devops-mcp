output "instance_id" {
  value = aws_instance.node.id
}

output "public_ip" {
  value = aws_eip.node.public_ip
}

output "status_api_url" {
  value = "http://${aws_eip.node.public_ip}:${var.status_api_nodeport}"
}
