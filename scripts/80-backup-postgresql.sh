#!/usr/bin/env bash
set -euo pipefail

KEYCLOAK_NAMESPACE="${KEYCLOAK_NAMESPACE:-keycloak}"
BACKUP_DIR="${BACKUP_DIR:-backups}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUTPUT="${1:-${BACKUP_DIR}/keycloak-${TIMESTAMP}.dump}"

umask 077
mkdir -p "$(dirname "${OUTPUT}")"

POSTGRES_POD="$(
  oc get pods \
    -n "${KEYCLOAK_NAMESPACE}" \
    -l name=keycloak-postgresql \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}'
)"

if [[ -z "${POSTGRES_POD}" ]]; then
  echo "ERROR: no se encontró el pod PostgreSQL en ejecución." >&2
  exit 1
fi

oc exec -n "${KEYCLOAK_NAMESPACE}" "${POSTGRES_POD}" -- \
  pg_isready -U keycloak -d keycloak

echo "Creando backup: ${OUTPUT}"
oc exec -n "${KEYCLOAK_NAMESPACE}" "${POSTGRES_POD}" -- \
  pg_dump \
    -U keycloak \
    -d keycloak \
    --format=custom \
    --no-owner \
    --no-privileges > "${OUTPUT}"

if [[ ! -s "${OUTPUT}" ]]; then
  echo "ERROR: el backup fue creado vacío." >&2
  exit 1
fi

sha256sum "${OUTPUT}" > "${OUTPUT}.sha256"

printf 'Backup:   %s\n' "${OUTPUT}"
printf 'Tamaño:   %s bytes\n' "$(stat -c '%s' "${OUTPUT}")"
printf 'Checksum: '
cut -d' ' -f1 "${OUTPUT}.sha256"

