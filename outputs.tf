output "vpn_server_public_ip" {
  description = "Dirección IP pública de tu servidor IPsec"
  value       = aws_instance.ipsec.public_ip
}

output "vpn_psk" {
  description = "Pre-Shared Key configurada en el servidor"
  value       = var.psk
  sensitive   = true
}
