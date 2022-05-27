output "elb_dns_name" {
  description = "The DNS name of the load balancer."
  value       = aws_elb.WebApp-terraform-elb.dns_name
}

output "elb_SG_name" {
  description = "The DNS name of the load balancer."
  value       = aws_elb.WebApp-terraform-elb.source_security_group
}