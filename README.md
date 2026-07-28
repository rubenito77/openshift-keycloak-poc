# OpenShift Keycloak POC

Prueba de concepto reproducible de Keycloak 26.7.0 sobre OpenShift 4.18. La POC instala
Keycloak con PostgreSQL persistente, crea el realm `platform` y compara dos versiones de una
misma aplicación: una pública y otra protegida mediante OpenID Connect.

## Estado

| Componente | Estado validado |
|---|---|
| OpenShift | 4.18.48 / Kubernetes 1.31.14 |
| Plataforma | AWS |
| StorageClass | `gp3-csi` |
| Keycloak Operator | 26.7.0, canal `fast`, aprobación manual |
| PostgreSQL | 15.18, PVC de 5 GiB |
| Keycloak | Pod listo y Route TLS edge |
| Realm `platform` | Importado; discovery OIDC responde `HTTP 200` |
| Aplicación pública | Próxima fase |
| Aplicación protegida | Próxima fase |

> El dominio de Red Hat Demo Platform es temporal. No se guardan credenciales ni secretos en Git.

## Arquitectura

```mermaid
flowchart TD
    U["Usuario / curl"] --> PUB["App pública"]
    U --> PRO["App protegida"]
    PRO --> KC["Keycloak realm platform"]
    KC --> PG["PostgreSQL + PVC gp3-csi"]
```

## Estructura

```text
.
├── apps/
│   └── README.md
├── config/
│   └── lab.env.example
├── docs/
│   └── poc-test-plan.md
├── manifests/
│   ├── 00-keycloak-operator.yaml
│   ├── 20-keycloak.yaml.tpl
│   └── 30-platform-realm.yaml
├── scripts/
│   ├── 00-inventory.sh
│   ├── 10-install-operator.sh
│   ├── 20-install-postgresql.sh
│   ├── 30-install-keycloak.sh
│   ├── 40-import-realm.sh
│   └── validate-platform.sh
└── README.md
```

## Requisitos

- OpenShift 4.18.
- Usuario con permisos `cluster-admin`.
- `oc`, `jq` y `envsubst`.
- Catálogos `community-operators` y `redhat-operators`.
- StorageClass dinámica.

## 1. Clonar y configurar

```bash
git clone https://github.com/rubenito77/openshift-keycloak-poc.git
cd openshift-keycloak-poc
chmod +x scripts/*.sh
cp config/lab.env.example config/lab.env
set -a
source config/lab.env
set +a
```

## 2. Inventario

```bash
./scripts/00-inventory.sh
```

La POC fue validada inicialmente contra:

```text
API:    https://api.cluster-bnj5s.bnj5s.sandbox3237.opentlc.com:6443
Apps:   apps.cluster-bnj5s.bnj5s.sandbox3237.opentlc.com
OCP:    4.18.48
```

## 3. Instalar el Operator

```bash
./scripts/10-install-operator.sh
```

La Subscription usa aprobación manual para evitar upgrades inesperados. Revisar:

```bash
oc get subscription.operators.coreos.com -n keycloak
oc get installplan.operators.coreos.com -n keycloak
```

Aprobar el InstallPlan seleccionado:

```bash
INSTALL_PLAN="$(oc get subscription.operators.coreos.com keycloak-operator \
  -n keycloak -o jsonpath='{.status.installPlanRef.name}')"

oc patch installplan.operators.coreos.com "${INSTALL_PLAN}" \
  -n keycloak --type merge -p '{"spec":{"approved":true}}'
```

Verificar:

```bash
oc wait --for=jsonpath='{.status.phase}'=Succeeded \
  csv/keycloak-operator.v26.7.0 -n keycloak --timeout=300s
```

## 4. Instalar PostgreSQL

```bash
./scripts/20-install-postgresql.sh
```

La plantilla genera automáticamente la contraseña y la almacena en
`secret/keycloak-postgresql`. No se debe decodificar ni subir a Git.

```bash
oc get pvc keycloak-postgresql -n keycloak
POSTGRES_POD="$(oc get pods -n keycloak -l name=keycloak-postgresql \
  -o jsonpath='{.items[0].metadata.name}')"
oc exec -n keycloak "${POSTGRES_POD}" -- pg_isready -U keycloak -d keycloak
```

## 5. Instalar Keycloak

```bash
./scripts/30-install-keycloak.sh
```

Verificar:

```bash
oc get keycloak,pods,service,ingress,route -n keycloak
curl -sS -o /dev/null -w 'HTTP %{http_code}\n' \
  "https://${KEYCLOAK_HOST}/"
```

`HTTP 302` en `/` es correcto. El discovery debe responder `HTTP 200`:

```bash
curl -fsS \
  "https://${KEYCLOAK_HOST}/realms/master/.well-known/openid-configuration" |
jq '{issuer,authorization_endpoint,token_endpoint,jwks_uri}'
```

## 6. Importar el realm

```bash
./scripts/40-import-realm.sh
```

El realm contiene:

- roles `platform-admin`, `platform-operator` y `platform-user`;
- grupos equivalentes;
- protección contra fuerza bruta;
- auditoría de eventos;
- registro público deshabilitado.

Validar:

```bash
curl -fsS \
  "https://${KEYCLOAK_HOST}/realms/platform/.well-known/openid-configuration" |
jq '{issuer,authorization_endpoint,token_endpoint,userinfo_endpoint,jwks_uri}'
```

Después de comprobar la importación:

```bash
oc delete keycloakrealmimport platform-realm -n keycloak
```

Esto limpia el Job temporal y no elimina el realm importado.

## 7. Validación integral

```bash
./scripts/validate-platform.sh
```

## 8. Escenario comparativo de aplicaciones

La siguiente fase despliega el mismo backend en dos variantes:

| Flujo | Sin autenticación | Con autenticación |
|---|---|---|
| `app-public` | `HTTP 200` directo | No aplica |
| `app-protected` | `HTTP 302` hacia Keycloak | `HTTP 200` después del login |

Además se demostrarán:

- credenciales inválidas;
- usuario autenticado sin rol: `HTTP 403`;
- usuario con `platform-user`: acceso permitido;
- logout y nueva redirección a Keycloak;
- validación del issuer, firma, roles y expiración del token.

La matriz completa está en [docs/poc-test-plan.md](docs/poc-test-plan.md).

## Seguridad

- No versionar `config/lab.env`.
- No almacenar contraseñas, tokens o client secrets.
- Mantener aprobación manual del Operator.
- Cambiar el administrador inicial y habilitar MFA fuera de una POC.
- PostgreSQL es una instancia única de laboratorio, no una topología HA.
- Las CR experimentales de clientes OIDC se evaluarán por separado.

## Próximas fases

1. Verificar y limpiar el Realm Import.
2. Crear cliente OIDC y usuarios de prueba.
3. Desplegar la aplicación pública.
4. Desplegar la aplicación protegida.
5. Automatizar pruebas positivas y negativas.
6. Agregar uninstall y backup/restore.
