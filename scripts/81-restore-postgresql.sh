#!/usr/bin/env bash
set -euo pipefail

KEYCLOAK_NAMESPACE="${KEYCLOAK_NAMESPACE:-keycloak}"
BACKUP_FILE="${1:-}"
CONFIRMATION="${2:-}"

usage() {
  cat <<'EOF'
Uso:
  ./scripts/81-restore-postgresql.sh BACKUP.dump --confirm-restore

La restauración:
  1. crea un backup preventivo;
  2. detiene el Operator y Keycloak;
  3. reemplaza el esquema de la base;
  4. inicia nuevamente el Operator y Keycloak.
EOF
}

if [[ -z "${BACKUP_FILE}" || "${CONFIRMATION}" != "--confirm-restore" ]]; then
  usage
  exit 2
fi

if [[ ! -s "${BACKUP_FILE}" ]]; then
  echo "ERROR: backup inexistente o vacío: ${BACKUP_FILE}" >&2
  exit 1
fi

if [[ -f "${BACKUP_FILE}.sha256" ]]; then
  EXPECTED_CHECKSUM="$(cut -d' ' -f1 "${BACKUP_FILE}.sha256")"
  ACTUAL_CHECKSUM="$(sha256sum "${BACKUP_FILE}" | cut -d' ' -f1)"
  if [[ "${ACTUAL_CHECKSUM}" != "${EXPECTED_CHECKSUM}" ]]; then
    echo "ERROR: checksum SHA-256 inválido para ${BACKUP_FILE}" >&2
    exit 1
  fi
  echo "Checksum SHA-256 verificado."
else
  echo "ADVERTENCIA: no existe ${BACKUP_FILE}.sha256"
fi

CURRENT_CONTEXT="$(oc config current-context)"
echo "Contexto:  ${CURRENT_CONTEXT}"
echo "Namespace: ${KEYCLOAK_NAMESPACE}"
echo "Backup:    ${BACKUP_FILE}"

PRE_RESTORE_BACKUP="backups/pre-restore-$(date -u +%Y%m%dT%H%M%SZ).dump"
./scripts/80-backup-postgresql.sh "${PRE_RESTORE_BACKUP}"

POSTGRES_POD="$(
  oc get pods \
    -n "${KEYCLOAK_NAMESPACE}" \
    -l name=keycloak-postgresql \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}'
)"
OPERATOR_REPLICAS="$(
  oc get deployment keycloak-operator \
    -n "${KEYCLOAK_NAMESPACE}" \
    -o jsonpath='{.spec.replicas}'
)"

restore_operator() {
  echo "Restaurando Keycloak Operator..."
  oc scale deployment keycloak-operator \
    -n "${KEYCLOAK_NAMESPACE}" \
    --replicas="${OPERATOR_REPLICAS}" >/dev/null || true
}
trap restore_operator EXIT

echo "Deteniendo reconciliación y Keycloak..."
oc scale deployment keycloak-operator \
  -n "${KEYCLOAK_NAMESPACE}" \
  --replicas=0
oc scale statefulset keycloak \
  -n "${KEYCLOAK_NAMESPACE}" \
  --replicas=0
oc wait \
  --for=delete pod/keycloak-0 \
  -n "${KEYCLOAK_NAMESPACE}" \
  --timeout=300s

echo "Copiando backup al pod PostgreSQL..."
oc exec -i -n "${KEYCLOAK_NAMESPACE}" "${POSTGRES_POD}" -- \
  sh -c 'umask 077; cat > /tmp/keycloak-restore.dump' < "${BACKUP_FILE}"

echo "Recreando el esquema public..."
oc exec -n "${KEYCLOAK_NAMESPACE}" "${POSTGRES_POD}" -- \
  psql \
    -U keycloak \
    -d keycloak \
    -v ON_ERROR_STOP=1 \
    -c 'DROP SCHEMA public CASCADE; CREATE SCHEMA public AUTHORIZATION keycloak;'

echo "Restaurando PostgreSQL..."
oc exec -n "${KEYCLOAK_NAMESPACE}" "${POSTGRES_POD}" -- \
  pg_restore \
    -U keycloak \
    -d keycloak \
    --exit-on-error \
    --no-owner \
    --no-privileges \
    /tmp/keycloak-restore.dump

oc exec -n "${KEYCLOAK_NAMESPACE}" "${POSTGRES_POD}" -- \
  rm -f /tmp/keycloak-restore.dump

restore_operator
trap - EXIT

oc rollout status deployment/keycloak-operator \
  -n "${KEYCLOAK_NAMESPACE}" \
  --timeout=300s

# La condición Ready del CR puede conservar temporalmente el valor anterior
# mientras el Operator vuelve a crear el pod. Esperar primero la reconciliación
# efectiva del StatefulSet evita validar la Route demasiado pronto.
for _ in $(seq 1 60); do
  KEYCLOAK_REPLICAS="$(
    oc get statefulset keycloak \
      -n "${KEYCLOAK_NAMESPACE}" \
      -o jsonpath='{.spec.replicas}' 2>/dev/null || true
  )"
  [[ "${KEYCLOAK_REPLICAS}" =~ ^[1-9][0-9]*$ ]] && break
  sleep 5
done

if [[ ! "${KEYCLOAK_REPLICAS:-}" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: el Operator no reactivó el StatefulSet de Keycloak." >&2
  exit 1
fi

oc rollout status statefulset/keycloak \
  -n "${KEYCLOAK_NAMESPACE}" \
  --timeout=600s
oc wait \
  --for=condition=Ready \
  pod/keycloak-0 \
  -n "${KEYCLOAK_NAMESPACE}" \
  --timeout=600s
oc wait \
  --for=condition=Ready \
  keycloak/keycloak \
  -n "${KEYCLOAK_NAMESPACE}" \
  --timeout=600s

KEYCLOAK_HOST="${KEYCLOAK_HOST:-$(
  oc get route \
    -n "${KEYCLOAK_NAMESPACE}" \
    -o jsonpath='{.items[0].spec.host}'
)}"
DISCOVERY_URL="https://${KEYCLOAK_HOST}/realms/master/.well-known/openid-configuration"
DISCOVERY_READY=false

for _ in $(seq 1 30); do
  HTTP_CODE="$(
    curl -sS \
      -o /dev/null \
      -w '%{http_code}' \
      "${DISCOVERY_URL}" || true
  )"
  if [[ "${HTTP_CODE}" == "200" ]]; then
    DISCOVERY_READY=true
    break
  fi
  sleep 10
done

if [[ "${DISCOVERY_READY}" != "true" ]]; then
  echo "ERROR: discovery OIDC no respondió HTTP 200: ${DISCOVERY_URL}" >&2
  exit 1
fi

echo "Restauración completada."
./scripts/validate-platform.sh
