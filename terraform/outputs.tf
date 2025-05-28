output "control_plane_public_ip" {
  value = aws_instance.control_plane[0].public_ip
}

output "control_plane_private_ip" {
  value = aws_instance.control_plane[0].private_ip
}

output "worker_public_ips" {
  value = {
    for i, worker in aws_instance.workers :
    "worker_${i + 1}" => worker.public_ip
  }
}

output "worker_private_ips" {
  value = {
    for i, worker in aws_instance.workers :
    "worker_${i + 1}" => worker.private_ip
  }
}