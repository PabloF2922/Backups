#!/bin/bash
# Restore físico desde un backup preparado creado por mariabackup
# Uso: MariaResotreReplica.sh [/ruta/backup_preparado] [--apply-master]

set -euo pipefail

BACKUP_PREPARED_DIR="${1:-/home/backup/mariabackup_prepared}"
APPLY_MASTER=0
if [[ "${2:-}" == "--apply-master" || "${1:-}" == "--apply-master" ]]; then
    APPLY_MASTER=1
    # si --apply-master fue primer arg y no se pasó ruta
    if [[ "$1" == "--apply-master" && -n "${2:-}" ]]; then
        BACKUP_PREPARED_DIR="${2}"
    fi
fi

MYSQLD_SERVICE="mariadb"
DATADIR="/var/lib/mysql"
LOGDIR="$(dirname $0)/LOGs"
mkdir -p "$LOGDIR"
LOGFILE="${LOGDIR}/mariarestore_$(date +%F).log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "[$(date '+%F %T')] INICIO RESTORE"

if [[ ! -d "$BACKUP_PREPARED_DIR" ]]; then
    echo "[ERROR] No existe el directorio de backup preparado: $BACKUP_PREPARED_DIR"
    exit 1
fi

echo "[*] Parando servicio mariadb..."
if command -v systemctl >/dev/null 2>&1; then
    systemctl stop "$MYSQLD_SERVICE"
else
    service "$MYSQLD_SERVICE" stop || true
fi

echo "[*] Copiando datos preparados al datadir ($DATADIR)"
# Hacer backup del datadir actual por seguridad
if [[ -d "$DATADIR" ]]; then
    mv "$DATADIR" "${DATADIR}.old_$(date +%F_%H%M)" || true
fi

mariabackup --copy-back --target-dir="$BACKUP_PREPARED_DIR"
chown -R mysql:mysql "$DATADIR"

# SELinux restore (si aplica)
if command -v restorecon >/dev/null 2>&1; then
    restorecon -Rv "$DATADIR" || true
fi

echo "[*] Iniciando servicio mariadb..."
if command -v systemctl >/dev/null 2>&1; then
    systemctl start "$MYSQLD_SERVICE"
else
    service "$MYSQLD_SERVICE" start || true
fi

echo "[*] Verificando estado del servicio"
sleep 2
if ! (mysql -e 'SELECT 1' >/dev/null 2>&1); then
    echo "[ERROR] MariaDB no arrancó correctamente. Revisa $LOGFILE"
    exit 1
fi

if [[ $APPLY_MASTER -eq 1 && -f "$BACKUP_PREPARED_DIR/xtrabackup_slave_info" ]]; then
    echo "[*] Aplicando coordenadas de replicación desde xtrabackup_slave_info"
    # Extraer la línea CHANGE MASTER TO ... (si existe)
    MASTER_CMD=$(grep -i '^CHANGE MASTER' "$BACKUP_PREPARED_DIR/xtrabackup_slave_info" || true)
    if [[ -n "$MASTER_CMD" ]]; then
        echo "Ejecutando: $MASTER_CMD"
        mysql -e "$MASTER_CMD"
        mysql -e "START SLAVE;"
        echo "[OK] Coordenadas aplicadas y réplica arrancada"
    else
        echo "[WARN] No se encontró CHANGE MASTER en xtrabackup_slave_info. Revisa el fichero manualmente: $BACKUP_PREPARED_DIR/xtrabackup_slave_info"
    fi
else
    if [[ -f "$BACKUP_PREPARED_DIR/xtrabackup_slave_info" ]]; then
        echo "[*] Para aplicar las coordenadas de replicación, vuelve a ejecutar con --apply-master"
        echo "Contenido de xtrabackup_slave_info:"
        sed -n '1,200p' "$BACKUP_PREPARED_DIR/xtrabackup_slave_info" || true
    fi
fi

echo "[$(date '+%F %T')] FIN RESTORE OK"
