#!/usr/bin/env bash
set -euo pipefail

KEYCLOAK_NAMESPACE="${KEYCLOAK_NAMESPACE:-keycloak}"
APPS_NAMESPACE="${APPS_NAMESPACE:-keycloak-poc-apps}"
CONFIRM_FLAG="${1:-}"
CONFIRM_VALUE="${2:-}"

if [[ "${CONFIRM_FLAG}" != "--confirm" || "${CONFIRM_VALUE}" != "DELETE-KEYCLOAK-POC" ]]; then
  cat <<'EOF'
Desinstalación cancelada.

Uso:
  ./scripts/99-uninstall.sh --confirm DELETE-KEYCLOAK-POC

La operación crea un backup y luego elimina:
  - namespace keycloak-poc-apps;
  - namespace keycloak;
  - Keycloak, PostgreSQL y el PVC.

No elimina las CRD compartidas de Keycloak.
EOF
  exit 2
fi

CURRENT_CONTEXT="$(oc config current-context)"
echo "Contexto: ${CURRENT_CONTEXT}"
echo "Se eliminarán los namespaces:"
printf '  - %s\n' "${APPS_NAMESPACE}" "${KEYCLOAK_NAMESPACE}"

BACKUP_FILE="backups/pre-uninstall-$(date -u +%Y%m%dT%H%M%SZ).dump"
./scripts/80-backup-postgresql.sh "${BACKUP_FILE}"

oc delete namespace "${APPS_NAMESPACE}" \
  --ignore-not-found=true \
  --wait=true \
  --timeout=300s
oc delete namespace "${KEYCLOAK_NAMESPACE}" \
  --ignore-not-found=true \
  --wait=true \
  --timeout=300s

echo "POC eliminada. Backup conservado localmente:"
echo "${BACKUP_FILE}"

