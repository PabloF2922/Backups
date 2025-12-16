**Guía: Backup físico con `mariabackup` desde una réplica MariaDB**

**Resumen**:
- **Objetivo**: Hacer backups físicos (hot backups) usando `mariabackup` desde una réplica MariaDB y dejar claros los pasos para preparar y restaurar.
- **Archivo de referencia**: [Mariadb/MariaBackupReplica.sh](Mariadb/MariaBackupReplica.sh)

**¿Es necesario `--prepare`?**
- **Sí**: El paso `--prepare` es obligatorio antes de restaurar un backup físico realizado con `mariabackup`.
- **Qué hace**: aplica los redo logs (roll forward) generados durante el backup para convertir los archivos de datos en un estado consistente. Sin `--prepare` los archivos están incompletos y no pueden arrancar el servidor.
- **Notas**: Para backups incrementales se usa un `--prepare --apply-log-only` intermedio y un `--prepare` final antes de la restauración.

**Flujo recomendado (resumen de pasos)**
1. **Comprobar réplica**: verificar que la réplica está saludable antes de hacer el backup.

```bash
# Comprobar estado de la réplica
mysql -e "SHOW SLAVE STATUS\G"
```

2. **Tomar el backup en la réplica (hot, sin detener el servidor)**
- Recomendación: añadir `--slave-info` para que `mariabackup` guarde las coordenadas de replicación (binlog/pos o GTID) en el backup.

```bash
mariabackup --backup \
  --user=backup --password='TU_PASS' \
  --target-dir=/ruta/backup_$(date +%F_%H-%M) \
  --slave-info
```

- Alternativa (opcional) para captura estricta de posición: detener el hilo SQL momentáneamente (`STOP SLAVE SQL_THREAD`) para evitar que la réplica aplique más relay logs; esto introduce lag en la réplica.

3. **(Opcional) Reiniciar hilo SQL** si lo detuviste:

```sql
START SLAVE SQL_THREAD;
```

4. **Preparar el backup** (en el mismo host o en el host donde vayas a restaurarlo):

```bash
mariabackup --prepare --target-dir=/ruta/backup_YYYY-MM-DD_HH-MM
```

- `--prepare` aplica los redo logs y deja los ficheros listos para copiar/arrancar.

5. **Restaurar** (ejemplo básico):
- Parar `mysqld` en el servidor de destino.
- Mover o vaciar el `datadir` actual.
- Copiar los archivos preparados al datadir.

```bash
# En el host donde se restaurará
systemctl stop mariadb
# (Opcional) mover datadir actual
mv /var/lib/mysql /var/lib/mysql.old
# Copiar los datos preparados al datadir
mariabackup --copy-back --target-dir=/ruta/backup_preparado
chown -R mysql:mysql /var/lib/mysql
# SE Linux: restorecon -Rv /var/lib/mysql (si aplica)
systemctl start mariadb
```

6. **Restaurar la réplica (si backup tomado en réplica)**:
- Si usaste `--slave-info`, encontrarás un fichero `xtrabackup_slave_info` en el backup con la instrucción `CHANGE MASTER TO ...` o las coordenadas necesarias.
- Ejecuta la instrucción contenida en ese fichero para posicionar la réplica al punto correcto.

```bash
# Ver ejemplo de contenido
cat /ruta/backup_preparado/xtrabackup_slave_info
# Dentro de MySQL ejecutar la instrucción CHANGE MASTER TO ...; o usar CHANGE REPLICATION SOURCE ... según versión
mysql -e "CHANGE MASTER TO MASTER_LOG_FILE='mysql-bin.000012', MASTER_LOG_POS=34567; START SLAVE;"
```

**Detalles importantes y buenas prácticas**
- **`--prepare` es imprescindible antes de intentar arrancar el servidor con esos archivos**.
- **`--slave-info`**: al hacer backups en una réplica es MUY recomendable usar `--slave-info` para capturar las coordenadas de replicación automáticamente.
- **Permisos y propiedad**: tras `--copy-back`, ajustar `chown -R mysql:mysql` en el datadir y revisar SELinux/ACLs.
- **Pruebas**: automatiza restauras periódicas en un entorno de staging para validar que los backups son usables.
- **Incrementales**: si usas backups incrementales, aplica los `--prepare --apply-log-only` para cada incremental y al final un `--prepare` sin `--apply-log-only`.
- **Espacio y rotación**: comprime y rota los archivos (`tar.gz`, `borg`, `restic`, etc.) y conserva un historial según tus RPO/RTO.

**Sugerencias rápidas de mejora para tu script** ([Mariadb/MariaBackupReplica.sh](Mariadb/MariaBackupReplica.sh)):
- Añadir `--slave-info` al comando `mariabackup --backup` para capturar los datos de replicación.
- Considerar manejo de errores más robusto (comprobar salida de `mariabackup`, códigos de retorno, espacio disponible).
- Evitar `cp -R` entre `BACKUP_DIR` y `PREPARED_DIR` (mejor usar `mariabackup --prepare --target-dir` directamente sobre el backup original o mover en lugar de copiar para ahorrar I/O).
- Incluir verificación de que `mariabackup` esté presente y versión compatible.

**Ejemplo de ajuste del comando en tu script** (sugerencia):

```bash
mariabackup --backup \
  --user="$MYSQL_USER" --password="$MYSQL_PASS" \
  --target-dir="$BACKUP_DIR" \
  --slave-info
```

**Checks post-backup**:
- Revisar el log de `mariabackup` para errores.
- Comprobar que existe `xtrabackup_slave_info` y/o `backup-my.cnf` en el `target-dir`.
- Revisar tamaño, integridad (prueba de restore en staging).

**Resumen final**:
- Toma el backup en la réplica con `--slave-info` para capturar coordenadas.
- `--prepare` es obligatorio antes de restaurar; aplica redo logs y deja el backup consistente.
- Probar la restauración periódicamente y automatizar rotación/retención.

Si quieres, puedo:
- Modificar directamente `Mariadb/MariaBackupReplica.sh` para incluir `--slave-info` y otras mejoras.
- Añadir un script de restore de ejemplo y pruebas automáticas.
