apiVersion: k8s.keycloak.org/v2beta1
kind: Keycloak
metadata:
  name: keycloak
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: keycloak
    app.kubernetes.io/part-of: keycloak-lab
spec:
  instances: 1
  db:
    vendor: postgres
    host: keycloak-postgresql
    port: 5432
    database: keycloak
    usernameSecret:
      name: keycloak-postgresql
      key: database-user
    passwordSecret:
      name: keycloak-postgresql
      key: database-password
  http:
    httpEnabled: true
  hostname:
    hostname: ${KEYCLOAK_HOST}
  proxy:
    headers: xforwarded
  ingress:
    enabled: true
    className: openshift-default
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: "2"
      memory: 2Gi

