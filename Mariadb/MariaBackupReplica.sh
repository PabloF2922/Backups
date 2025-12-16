#!/bin/bash
# Backup físico con mariabackup desde la réplica
# Autor: Pablo Fernandez

set -euo pipefail

### CONFIGURACIÓN ###
BACKUP_DIR="/backup/mariabackup_raw"
PREPARED_DIR="/backup/mariabackup_prepared"
FINAL_DIR="/backup/mariabackup_final"
#NAS_DIR="/mnt/nas"
LOGDIR="$(dirname $0)/LOGs"
MYSQL_USER="backup"
MYSQL_PASS="PASSWORD"
# Asegúrate de ajustar estas rutas a tu sistema y que haya espacio suficiente

mkdir -p "$LOGDIR" "$BACKUP_DIR" "$FINAL_DIR" "$PREPARED_DIR"

LOGFILE="${LOGDIR}/mariabackup_$(date +%F).log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "[$(date '+%F %T')] INICIO BACKUP"
echo "----------------------------------"

### 1️⃣ VALIDAR ESTADO DE REPLICA ###
echo "[*] Validando estado de réplica..."

IO=$(mariadb -N -e "SHOW SLAVE STATUS" | grep Slave_IO_Running | awk '{print $2}')
SQL=$(mariadb -N -e "SHOW SLAVE STATUS" | grep Slave_SQL_Running | awk '{print $2}')

if [[ "$IO" != "Yes" || "$SQL" != "Yes" ]]; then
    echo "[ERROR] La réplica NO está en buen estado."
    mariadb -e "SHOW SLAVE STATUS\G"
    exit 1
fi

echo "[OK] Réplica corriendo: IO=$IO / SQL=$SQL"

### 2️⃣ TOMAR BACKUP FÍSICO (HOT, SIN PARAR REPLICA) ###
echo "[*] Iniciando backup físico con mariabackup..."

rm -rf "$BACKUP_DIR"/*
mariabackup --backup \
    --user="$MYSQL_USER" \
    --password="$MYSQL_PASS" \
    --target-dir="$BACKUP_DIR" \
    --slave-info

# Comprobar que generó la información de réplica
if [[ ! -f "${BACKUP_DIR}/xtrabackup_slave_info" ]]; then
    echo "[WARN] No se encontró xtrabackup_slave_info en ${BACKUP_DIR} (revisa --slave-info)"
fi

echo "[OK] Backup físico completado."

### 3️⃣ PREPARAR BACKUP (APLICAR REDO LOGS) ###
echo "[*] Preparando backup (apply-log)..."

rm -rf "$PREPARED_DIR"/*
cp -R "$BACKUP_DIR" "$PREPARED_DIR"

mariabackup --prepare --target-dir="$PREPARED_DIR"

echo "[OK] Backup preparado."

### 4️⃣ COMPRIMIR BACKUP FINAL ###
echo "[*] Comprimiendo backup final..."

TIMESTAMP=$(date +%F_%H-%M)
FINAL_TAR="${FINAL_DIR}/mariadb_backup_${TIMESTAMP}.tar.gz"

tar -czf "$FINAL_TAR" -C "$PREPARED_DIR" .

echo "[OK] Backup comprimido: $FINAL_TAR"


### 6️⃣ MOSTRAR POSICIÓN BINLOG / GTID ###
echo "[*] Info del binlog al momento del backup:"
mariadb -e "SHOW SLAVE STATUS\G" | egrep 'Relay_Master_Log_File|Exec_Master_Log_Pos|Gtid_IO_Pos'

echo "----------------------------------"
echo "[$(date '+%F %T')] FIN BACKUP OK"
