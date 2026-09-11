#!/usr/bin/env bash
#
# deploy.sh
# ---------
# Automatiza, en un solo comando, los pasos manuales descritos en la
# sección 4 del README ("Comandos de ejecución"). No reemplaza ese
# conocimiento —para el taller sigue siendo importante entender qué hace
# cada paso por separado—, pero evita repetirlos a mano cada vez que se
# quiere recrear el entorno desde cero (por ejemplo, tras un
# `vagrant destroy`).
#
# Pasos que ejecuta, en orden:
#   1) Instala las colecciones de Ansible listadas en requirements.yml.
#   2) Levanta la VM con Vagrant usando el provider VirtualBox.
#   3) Genera .vagrant-ssh-config a partir de `vagrant ssh-config`, que
#      es lo que usa Ansible para conectarse (ver ansible_ssh_common_args
#      en inventory/hosts.yml).
#   4) Ejecuta el playbook site.yml (o una variante, según el modo).
#
# Uso:
#   ./deploy.sh              Despliegue normal: vagrant up + ansible-playbook.
#   ./deploy.sh --check      Igual, pero el playbook corre en modo
#                            --check --diff (simulación, no aplica cambios).
#   ./deploy.sh --twice      Ejecuta el playbook DOS veces seguidas, para
#                            comprobar en un solo paso que la segunda
#                            corrida no reporta cambios (idempotencia).
#   ./deploy.sh --skip-vm    Omite los pasos 2 y 3 (no toca Vagrant) y va
#                            directo al playbook; útil si la VM ya está
#                            levantada y .vagrant-ssh-config ya existe.
#
# El script se detiene ante el primer error (set -e) para no continuar
# con pasos posteriores sobre un estado a medio construir.

set -euo pipefail

# Ubicarse siempre en la carpeta del proyecto, sin importar desde dónde
# se invoque el script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

VM_NAME="dns-dhcp01"
SSH_CONFIG_FILE=".vagrant-ssh-config"
MODE="${1:-}"

log() {
    # Pequeño helper para que la salida del script sea fácil de seguir
    # en pantalla, diferenciándola de la salida propia de vagrant/ansible.
    echo ""
    echo "==> $1"
}

if [[ "$MODE" != "--skip-vm" ]]; then
    log "[1/4] Instalando colecciones de Ansible (requirements.yml)"
    ansible-galaxy collection install -r requirements.yml

    log "[2/4] Levantando la máquina virtual con Vagrant (VirtualBox)"
    vagrant up --provider=virtualbox

    log "[3/4] Generando configuración SSH para Ansible ($SSH_CONFIG_FILE)"
    vagrant ssh-config "$VM_NAME" > "$SSH_CONFIG_FILE"
else
    log "Modo --skip-vm: se omite Vagrant, se asume que la VM ya está arriba"
fi

log "[4/4] Ejecutando el playbook"
case "$MODE" in
    --check)
        ansible-playbook site.yml --check --diff
        ;;
    --twice)
        echo "---- Primera ejecución ----"
        ansible-playbook site.yml
        echo ""
        echo "---- Segunda ejecución (debe reportar 0 changed) ----"
        ansible-playbook site.yml
        ;;
    ""|--skip-vm)
        ansible-playbook site.yml
        ;;
    *)
        echo "Opción no reconocida: $MODE"
        echo "Uso: $0 [--check|--twice|--skip-vm]"
        exit 1
        ;;
esac

log "Listo. Verifica los servicios con los comandos de la sección 5 del README."
