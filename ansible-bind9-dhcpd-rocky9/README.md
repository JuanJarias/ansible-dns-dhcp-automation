# Automatización de BIND9 (DNS) y DHCPD sobre Rocky Linux 9 con Ansible

## Propósito

Este proyecto automatiza, mediante Ansible, la instalación y configuración
**idempotente** de dos servicios de red sobre Rocky Linux 9:

- **BIND9 (`named`)**: servidor DNS autoritativo para el dominio `lab.icesi.local`,
  con zona directa e inversa.
- **DHCPD (`dhcpd`)**: servidor DHCP que entrega direcciones IP dinámicas en la
  subred `192.168.100.0/24` y permite reservas estáticas por MAC.

El playbook puede ejecutarse tantas veces como sea necesario: si la
infraestructura ya está en el estado deseado, Ansible no reporta cambios
(`changed=0`) y no genera errores.

## Estructura del repositorio

```
.
├── ansible.cfg              # Configuración del proyecto (inventario, become, etc.)
├── site.yml                 # Playbook principal (orquesta los roles)
├── requirements.yml         # Colecciones externas necesarias (ansible.posix)
├── inventory/
│   └── hosts.ini             # Inventario de ejemplo (grupos dns_servers / dhcp_servers)
├── group_vars/
│   ├── all.yml                # Variables comunes (dominio, red, zona inversa)
│   ├── dns_servers.yml        # Variables específicas de BIND9
│   └── dhcp_servers.yml       # Variables específicas de DHCPD
└── roles/
    ├── bind9/
    │   ├── defaults/main.yml
    │   ├── handlers/main.yml
    │   ├── tasks/main.yml
    │   └── templates/
    │       ├── named.conf.j2
    │       ├── forward.zone.j2
    │       └── reverse.zone.j2
    └── dhcpd/
        ├── defaults/main.yml
        ├── handlers/main.yml
        ├── tasks/main.yml
        └── templates/
            └── dhcpd.conf.j2
```

## Requisitos previos

- Ansible >= 2.14 en la máquina de control.
- Una o más VMs con **Rocky Linux 9** accesibles por SSH, con un usuario que
  tenga privilegios `sudo`.
- Acceso a internet en las VMs para instalar paquetes vía `dnf` (o un
  repositorio local equivalente).

## Configuración antes de ejecutar

1. Editar `inventory/hosts.ini` con las IPs/hostnames reales de tus VMs y el
   usuario SSH correspondiente.
2. Ajustar variables en `group_vars/all.yml`, `group_vars/dns_servers.yml` y
   `group_vars/dhcp_servers.yml` según tu topología de red (dominio, subred,
   rango DHCP, registros DNS, etc.).
3. Instalar la colección requerida:

   ```bash
   ansible-galaxy collection install -r requirements.yml
   ```

## Comandos de ejecución

Verificar conectividad con los hosts del inventario:

```bash
ansible all -m ping
```

Ejecutar el playbook completo:

```bash
ansible-playbook site.yml
```

Ejecutar en modo *check* (simulación, sin aplicar cambios) para revisar qué
haría el playbook:

```bash
ansible-playbook site.yml --check --diff
```

Ejecutar solo el rol de DNS o solo el de DHCP usando límites por grupo:

```bash
ansible-playbook site.yml --limit dns_servers
ansible-playbook site.yml --limit dhcp_servers
```

## Validación de idempotencia

Para comprobar que el playbook es idempotente, ejecútalo dos veces seguidas:

```bash
ansible-playbook site.yml
ansible-playbook site.yml
```

En la segunda ejecución, el resumen final (`PLAY RECAP`) debe mostrar
`changed=0` y `failed=0` en todos los hosts, ya que:

- Los paquetes (`dnf`) solo se instalan si no están presentes.
- Las plantillas (`template`) solo se reescriben si el contenido renderizado
  difiere del archivo actual.
- Las tareas de validación de sintaxis (`named-checkconf`, `named-checkzone`,
  `dhcpd -t`) se marcan explícitamente con `changed_when: false`.
- Los servicios (`service`) solo cambian de estado si no están ya
  `started`/`enabled`.
- Las reglas de `firewalld` solo se modifican si el servicio no estaba ya
  habilitado.

## Notas de diseño

- El número de serie de las zonas DNS (`bind_zone_serial`) se define como
  variable en `group_vars/dns_servers.yml` y debe incrementarse manualmente
  cada vez que se modifiquen los registros, siguiendo la convención
  `YYYYMMDDxx`.
- Las plantillas usan `validate:` (en `named.conf`) y tareas de verificación
  posteriores (`named-checkzone`, `dhcpd -t`) para evitar dejar el servicio en
  un estado inválido.
- Los *handlers* (`restart named`, `restart dhcpd`) solo se disparan cuando
  una tarea realmente modifica la configuración, evitando reinicios
  innecesarios del servicio.
