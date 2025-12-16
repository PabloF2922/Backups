# Diff de cambios aplicados a MariaBackupReplica.sh

A continuación se muestra el diff (formato unified) con las modificaciones realizadas sobre `MariaBackupReplica.sh`.

```diff
*** a/Mariadb/MariaBackupReplica.sh
*** b/Mariadb/MariaBackupReplica.sh
@@
 MYSQL_PASS="PASSWORD"
+# Asegúrate de ajustar estas rutas a tu sistema y que haya espacio suficiente
@@
 rm -rf "$BACKUP_DIR"/*
-mariabackup --backup \
-    --user="$MYSQL_USER" \
-    --password="$MYSQL_PASS" \
-    --target-dir="$BACKUP_DIR"
+mariabackup --backup \
+    --user="$MYSQL_USER" \
+    --password="$MYSQL_PASS" \
+    --target-dir="$BACKUP_DIR" \
+    --slave-info
+
+# Comprobar que generó la información de réplica
+if [[ ! -f "${BACKUP_DIR}/xtrabackup_slave_info" ]]; then
+    echo "[WARN] No se encontró xtrabackup_slave_info en ${BACKUP_DIR} (revisa --slave-info)"
+fi
@@
-echo "[*] Preparando backup (apply-log)..."
-
-rm -rf "$PREPARED_DIR"/*
-cp -R "$BACKUP_DIR" "$PREPARED_DIR"
-
-mariabackup --prepare --target-dir="$PREPARED_DIR"
+echo "[*] Preparando backup (apply-log)..."
+
+### Preparar el backup directamente en el directorio de backup (más eficiente)
+mariabackup --prepare --target-dir="$BACKUP_DIR"
+
+# Mover los archivos preparados al directorio preparado (evita copiar)
+rm -rf "${PREPARED_DIR:?}"/*
+mv "$BACKUP_DIR"/* "$PREPARED_DIR"/ || true
+
+echo "[INFO] Backup preparado en $PREPARED_DIR"
*** End diff
```

Notas:
- Se añadió `--slave-info` al comando de backup para conservar coordenadas de replicación en `xtrabackup_slave_info`.
- Se sustituye la copia completa previa del backup por un `--prepare` in-place y un `mv` al directorio `PREPARED_DIR`, para reducir I/O y tiempo.
- Se añadió una comprobación de la existencia de `xtrabackup_slave_info` y mensajes informativos.

Archivo original: `Mariadb/MariaBackupReplica.sh`
