variable "aws_region" {
  description = "Región AWS donde desplegar"
  type        = string
  default     = "mx-central-1"
}

variable "instance_type" {
  description = "Tipo de instancia EC2"
  type        = string
  default     = "t3.micro"
}

variable "psk" {
  description = "Clave pre-compartida para IPsec (PSK)"
  type        = string
  default     = "********REDACTED********"
}

variable "client_net_cidr" {
  description = "Red interna que usarán los clientes VPN"
  type        = string
  default     = "192.168.178.0/24"
}

variable "ssh_public_key" {
  description = "Clave pública SSH para acceder a la instancia"
  type        = string
}
