#!/usr/bin/env bash
set -euo pipefail

KEYCLOAK_NAMESPACE="${KEYCLOAK_NAMESPACE:-keycloak}"
APPS_NAMESPACE="${APPS_NAMESPACE:-keycloak-poc-apps}"

oc get servicemonitor keycloak -n "${KEYCLOAK_NAMESPACE}"

APP_POD="$(
  oc get pods \
    -n "${APPS_NAMESPACE}" \
    -l app=app-public \
    -o jsonpath='{.items[0].metadata.name}'
)"

echo "Health ready:"
oc exec -n "${APPS_NAMESPACE}" "${APP_POD}" -- \
  python -c '
import json
import urllib.request
data = json.load(urllib.request.urlopen(
    "http://keycloak-service.keycloak.svc:9000/health/ready",
    timeout=10
))
print(json.dumps(data, indent=2))
'

echo
echo "Métricas representativas:"
oc exec -n "${APPS_NAMESPACE}" "${APP_POD}" -- \
  python -c '
import urllib.request
text = urllib.request.urlopen(
    "http://keycloak-service.keycloak.svc:9000/metrics",
    timeout=10
).read().decode()
names = []
for line in text.splitlines():
    if line.startswith("# HELP "):
        name = line.split()[2]
        if name not in names:
            names.append(name)
for name in names[:20]:
    print(name)
print("metric_families_detected=" + str(len(names)))
'

