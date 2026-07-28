# Operación: observabilidad, backup, restore y desinstalación

## Observabilidad

Keycloak expone health y métricas en la interfaz de gestión, puerto `9000`. Este puerto no
debe exponerse mediante la Route de usuarios.

Habilitar:

```bash
./scripts/90-enable-observability.sh
```

El script activa `metrics-enabled`, configura el `ServiceMonitor` y espera que Keycloak vuelva
a estar listo.

Validar:

```bash
./scripts/91-validate-observability.sh
```

Comprobaciones:

- `ServiceMonitor/keycloak`;
- `/health/ready`;
- `/metrics`;
- puerto de gestión no expuesto por Route.

Para que Prometheus User Workload Monitoring recolecte el ServiceMonitor, debe estar habilitado
en el clúster y permitir el namespace `keycloak`.

## Backup

```bash
./scripts/80-backup-postgresql.sh
```

Salida:

```text
backups/keycloak-YYYYMMDDTHHMMSSZ.dump
backups/keycloak-YYYYMMDDTHHMMSSZ.dump.sha256
```

Características:

- formato custom de `pg_dump`;
- sin ownership ni privilegios dependientes del entorno;
- permisos locales restrictivos mediante `umask 077`;
- checksum SHA-256;
- ningún Secret se imprime.

Validar el checksum:

```bash
sha256sum --check backups/keycloak-*.dump.sha256
```

Copiar el backup a almacenamiento duradero y cifrado. El directorio `backups/` está excluido
de Git.

## Restore

La restauración reemplaza todo el esquema `public` de Keycloak. Requiere indisponibilidad.

```bash
./scripts/81-restore-postgresql.sh \
  backups/keycloak-YYYYMMDDTHHMMSSZ.dump \
  --confirm-restore
```

El script:

1. verifica archivo y checksum;
2. crea un backup preventivo;
3. detiene el Operator y el StatefulSet;
4. recrea el esquema `public`;
5. ejecuta `pg_restore`;
6. inicia el Operator;
7. espera `Ready=True`;
8. ejecuta validaciones.

No restaurar un backup de una versión de Keycloak incompatible sin revisar primero las notas
de migración.

## Prueba de recuperación recomendada

1. Crear un realm o usuario descartable.
2. Ejecutar backup.
3. Modificar o eliminar el objeto descartable.
4. Ejecutar restore.
5. Confirmar que el estado anterior reaparece.
6. Ejecutar `./scripts/70-test-poc.sh`.

Una copia que nunca fue restaurada en una prueba no debe considerarse un backup validado.

## Desinstalación

La desinstalación es destructiva y elimina el PVC:

```bash
./scripts/99-uninstall.sh --confirm DELETE-KEYCLOAK-POC
```

Antes de borrar, el script crea automáticamente un backup local.

No elimina las CRD de Keycloak porque son recursos de alcance cluster y podrían ser compartidas
por otros Operators o namespaces.
