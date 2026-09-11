# Automatización DHCP + DNS (BIND9) sobre Rocky Linux 9 con Ansible

## 1. Propósito del proyecto

Este repositorio automatiza el ciclo completo de despliegue de un servidor
de red básico —DHCP y DNS— sobre Rocky Linux 9, desde la creación de la
máquina virtual hasta la validación de que ambos servicios responden
correctamente. El objetivo del taller es que el estudiante entienda cómo
se estructura un proyecto de Ansible de tamaño real: separación de
responsabilidades por rol, variables parametrizadas, uso de módulos
nativos en vez de comandos sueltos, y verificación de idempotencia como
parte del flujo de trabajo, no como una ocurrencia tardía.

La creación de la máquina virtual se delega en Vagrant en lugar de
automatizarla con un rol de Ansible (por ejemplo, con `community.libvirt`).
La razón es pragmática para un entorno de taller: Vagrant resuelve de
forma declarativa y portable la descarga de la imagen, la configuración
de red privada y el acceso SSH inicial, sin que cada estudiante tenga que
depurar diferencias de virtualización en su propia máquina. Vagrant
soporta tanto `libvirt` (recomendado en Linux, por rendimiento y por usar
KVM nativo) como `virtualbox` (alternativa multiplataforma para quien no
tenga KVM disponible), y el mismo `Vagrantfile` sirve para ambos casos sin
modificarlo. A propósito **no** se usa el provisioner `ansible` integrado
de Vagrant: el playbook se ejecuta manualmente con `ansible-playbook` para
que cada corrida —incluida la segunda, que debe reportar cero cambios—
sea un paso visible y deliberado del taller.

Los roles se dividen en `bootstrap` (garantizar que el nodo tiene Python
y está actualizado, sin asumir nada sobre su estado inicial),
`provisioning` (identidad del nodo dentro de este proyecto: hostname,
`/etc/hosts`, huso horario), `dhcpd` y `bind9` (cada servicio, aislado).
Esta separación existe porque cada uno tiene un ciclo de vida distinto:
`bootstrap` corre una sola vez por el ciclo de vida de la VM y no depende
de facts; `provisioning` es idempotente pero conceptualmente distinto de
"instalar el sistema operativo"; y `dhcpd`/`bind9` deben poder tocarse,
probarse o incluso eliminarse de forma independiente sin arrastrar código
del otro servicio.

## 2. Prerrequisitos

En la máquina de control (tu laptop o la VM desde la que administras)
necesitas:

- **Ansible** >= 2.15 (`pip install --user ansible-core` o el paquete de tu
  distribución).
- **Colecciones de Ansible** listadas en `requirements.yml`.
- **Vagrant** >= 2.3.
- Un hipervisor: **libvirt/QEMU-KVM** (Linux) o **VirtualBox** (cualquier
  SO), y el plugin correspondiente de Vagrant si usas libvirt:
  `vagrant plugin install vagrant-libvirt`.
- Acceso a internet saliente desde la máquina de control (para descargar
  la box de Vagrant y las colecciones de Ansible) y desde la VM (para
  `dnf update` y los forwarders de DNS).

## 3. Estructura del repositorio

```
.
├── ansible.cfg              # Configuración de Ansible (inventario, become, etc.)
├── requirements.yml         # Colecciones de Galaxy requeridas
├── Vagrantfile              # Definición y arranque de la VM (Rocky Linux 9)
├── site.yml                 # Playbook orquestador
├── inventory/
│   └── hosts.yml            # Inventario estático (IP fija de la red privada)
├── group_vars/
│   ├── all.yml               # Variables comunes (dominio, red, paquetes base)
│   ├── dhcp_servers.yml       # Variables del rol dhcpd
│   └── dns_servers.yml        # Variables del rol bind9
└── roles/
    ├── bootstrap/            # "Plomería": deja el nodo listo para Ansible
    ├── provisioning/         # "Plomería": identidad básica del nodo
    ├── dhcpd/                # LÓGICA DEL TALLER: servidor DHCP
    └── bind9/                # LÓGICA DEL TALLER: servidor DNS
```

Si tu interés es la parte de **servicios de red** (que es el objetivo del
taller), puedes tratar `bootstrap/` y `provisioning/` como caja negra: solo
necesitas saber que garantizan un nodo con Python, paquetes actualizados,
hostname correcto y resolución básica en `/etc/hosts`. Donde vale la pena
detenerse a leer con cuidado es en `roles/dhcpd/` y `roles/bind9/`
(tareas, *handlers* y plantillas), y en `group_vars/dhcp_servers.yml` /
`group_vars/dns_servers.yml`, que es donde vive toda la configuración de
red del laboratorio (rangos DHCP, dominio, registros DNS, zona inversa).

## 4. Comandos de ejecución

```bash
# 1) Clonar el repositorio y entrar en él
git clone <url-del-repositorio> ansible-dhcp-dns-rocky9
cd ansible-dhcp-dns-rocky9

# 2) Instalar las colecciones de Ansible requeridas
ansible-galaxy collection install -r requirements.yml

# 3) Levantar la máquina virtual con Vagrant
#    (usa --provider=libvirt o --provider=virtualbox según tu entorno;
#    si no se especifica, Vagrant usa el primer provider disponible)
vagrant up --provider=libvirt

# 4) Generar el archivo de configuración SSH que usará Ansible
#    (la ruta de la clave privada y el puerto dependen del provider)
vagrant ssh-config dns-dhcp01 > .vagrant-ssh-config

# 5) Ejecutar el playbook completo
ansible-playbook site.yml

# --- Variantes útiles ---

# Modo simulación: ver qué cambiaría sin aplicar nada
ansible-playbook site.yml --check --diff

# Limitar la ejecución a un grupo o host específico
ansible-playbook site.yml --limit dns_servers

# Ejecutar solo las tareas de un rol concreto (usando tags de rol)
ansible-playbook site.yml --tags dhcpd

# Segunda ejecución para comprobar idempotencia (no debe reportar "changed")
ansible-playbook site.yml
```

> Nota sobre `--tags`: los roles no declaran tags manuales adicionales
> porque Ansible ya asigna automáticamente el nombre del rol como tag
> implícito a todas sus tareas; por eso `--tags dhcpd` o `--tags bind9`
> funcionan sin configuración extra.

## 5. Verificación de los servicios

**DNS (desde la propia VM o desde el host, apuntando al servidor):**

```bash
# Resolución directa
dig @192.168.56.10 dns-dhcp01.lab.local
dig @192.168.56.10 www.lab.local

# Resolución inversa
dig @192.168.56.10 -x 192.168.56.10

# Alternativa con nslookup
nslookup dns-dhcp01.lab.local 192.168.56.10
```

Una respuesta correcta debe mostrar una sección `ANSWER` no vacía con el
registro `A` (o `PTR` en el caso inverso) esperado.

**DHCP (dentro de la VM):**

```bash
# Ver el estado del servicio
systemctl status dhcpd

# Ver los leases entregados hasta el momento
cat /var/lib/dhcpd/dhcpd.leases

# Verificar que solo está escuchando en la interfaz privada
ss -lunp | grep dhcpd
```

Para probar una asignación real de lease, conecta un segundo cliente
(otra VM o contenedor) a la misma red privada `192.168.56.0/24` y pídele
una IP por DHCP (`dhclient` en Linux); debería recibir una dirección
dentro del rango `192.168.56.100–192.168.56.200`.

## 6. Cómo se garantiza la idempotencia

No es solo "porque Ansible es idempotente por diseño": cada rol tiene un
mecanismo concreto que lo sostiene:

- **`bootstrap`**: la verificación de Python usa `raw` con
  `changed_when` explícito, que solo marca `changed` si de verdad tuvo
  que instalar el paquete (busca un marcador de texto que solo se
  imprime en ese caso). `dnf update` con `state: latest` ya es
  idempotente de forma nativa: si no hay paquetes por actualizar, el
  módulo reporta `ok`, no `changed`.
- **`provisioning`**: `ansible.builtin.hostname` y
  `community.general.timezone` son módulos declarativos: comparan el
  estado deseado contra el real y solo actúan si difieren.
  `lineinfile` compara la línea exacta antes de escribir.
- **`dhcpd` y `bind9`**: las plantillas (`template`) solo se marcan como
  `changed` si el contenido generado difiere del archivo existente en
  disco (Ansible compara un hash). El parámetro `validate` (`dhcpd -t`,
  `named-checkconf`, `named-checkzone`) se ejecuta en cada corrida sobre
  un archivo temporal, **antes** de decidir si reemplaza el archivo real,
  y no aporta su propio estado de "changed": es una condición de éxito/
  fallo, no una tarea aparte. Los *handlers* de reinicio (`notify`) solo
  se disparan cuando la tarea que los notifica reportó `changed`, así que
  una segunda ejecución sin cambios no reinicia ningún servicio.
- **Serial DNS estático**: el serial de las zonas (`dns_zone_serial`) es
  una variable fija en `group_vars/dns_servers.yml`, no un timestamp
  generado en cada ejecución. Si fuera dinámico, el contenido de la zona
  cambiaría en cada corrida y rompería la idempotencia por diseño.
- **`restorecon`**: es la única tarea que usa `command` en vez de un
  módulo nativo (no existe módulo equivalente para reetiquetar SELinux
  de forma masiva). Su `changed_when` busca la palabra `Relabeled`, que
  `restorecon -v` solo imprime para los archivos que efectivamente
  reetiquetó; si no hay nada que corregir, la tarea se reporta como `ok`.

## 7. Troubleshooting

**a) `dhcpd` no arranca o falla con "no address family support"**
Casi siempre significa que `DHCPDARGS` en `/etc/sysconfig/dhcpd` apunta a
una interfaz que no existe con ese nombre en tu VM. Verifica el nombre
real con `ip a` dentro de la VM y ajústalo en
`group_vars/all.yml` (`project_network.interface`) si tu box no usa
`eth1` para la red privada.

**b) BIND9/named falla al iniciar con errores de permisos (`permission denied`) en los archivos de zona**
Es SELinux bloqueando el acceso, generalmente porque se editó un archivo
de zona a mano fuera de Ansible y quedó con el contexto por defecto
(`user_tmp_t` o similar). Ejecuta manualmente
`restorecon -Rv /etc/named /etc/named.conf /var/named` y vuelve a
correr el playbook; la tarea homónima del rol `bind9` debería mantenerlo
resuelto en adelante.

**c) `dig`/`nslookup` no obtienen respuesta desde el host, pero sí desde dentro de la VM**
Revisa que `firewalld` tenga el servicio `dns` (o `dhcp`) habilitado con
`firewall-cmd --list-services` dentro de la VM. Si el rol correspondiente
ya corrió, ambos deberían aparecer; si no, es señal de que la tarea de
`ansible.posix.firewalld` falló silenciosamente por falta de la colección
`ansible.posix` (repite el paso 2 de la sección de comandos de
ejecución).

**d) `wait_for_connection` del rol `bootstrap` agota el timeout (180s) justo después de `vagrant up`**
El arranque de la VM y el sshd pueden tardar más de lo que tarda
`vagrant up` en devolver el prompt, especialmente en el primer arranque
tras descargar la box. Espera unos segundos adicionales y vuelve a
ejecutar `ansible-playbook site.yml`; si el problema persiste, aumenta el
valor de `timeout` en la tarea `wait_for_connection` del rol `bootstrap`.
