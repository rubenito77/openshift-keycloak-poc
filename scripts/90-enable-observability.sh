#!/usr/bin/env bash
set -euo pipefail

KEYCLOAK_NAMESPACE="${KEYCLOAK_NAMESPACE:-keycloak}"

if ! oc get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
  echo "ERROR: ServiceMonitor CRD no está instalada." >&2
  exit 1
fi

oc patch keycloak keycloak \
  -n "${KEYCLOAK_NAMESPACE}" \
  --type merge \
  -p '{
    "spec": {
      "additionalOptions": [
        {
          "name": "metrics-enabled",
          "value": "true"
        }
      ],
      "serviceMonitor": {
        "enabled": true,
        "interval": "30s",
        "scrapeTimeout": "10s",
        "labels": {
          "app.kubernetes.io/part-of": "keycloak-lab"
        }
      }
    }
  }'

oc wait \
  --for=condition=Ready \
  keycloak/keycloak \
  -n "${KEYCLOAK_NAMESPACE}" \
  --timeout=600s

echo "ServiceMonitor:"
oc get servicemonitor keycloak \
  -n "${KEYCLOAK_NAMESPACE}" \
  -o custom-columns='NAME:.metadata.name,INTERVAL:.spec.endpoints[0].interval,PATH:.spec.endpoints[0].path,PORT:.spec.endpoints[0].port'

echo
echo "Service de gestión:"
oc get service keycloak-service \
  -n "${KEYCLOAK_NAMESPACE}" \
  -o jsonpath='{range .spec.ports[*]}{.name}={.port}{"\n"}{end}'

echo
echo "La Route pública continúa exponiendo sólo el puerto de aplicación."
oc get route \
  -n "${KEYCLOAK_NAMESPACE}" \
  -o custom-columns='NAME:.metadata.name,SERVICE:.spec.to.name,PORT:.spec.port.targetPort,TERMINATION:.spec.tls.termination'

