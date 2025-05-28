all:
  vars:
    ansible_ssh_private_key_file: ${private_key_file}
    ansible_user: ${ssh_user}
    ansible_python_interpreter: /usr/bin/python3
  children:
    controls:
      hosts:
%{ if control_plane_ip != null ~}
        control_plane:
          ansible_host: ${control_plane_ip}
%{ endif ~}
    workers:
      hosts:
%{ for name, ip in worker_ip ~}
        ${name}:
          ansible_host: ${ip}
%{ endfor ~}
    servers:
      children:
        controls:
        workers: