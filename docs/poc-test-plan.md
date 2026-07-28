# Plan de pruebas de la POC

## Objetivo

Demostrar con evidencia reproducible la diferencia entre una aplicación expuesta directamente
y la misma aplicación protegida mediante Keycloak.

## Matriz

| ID | Escenario | Resultado esperado |
|---|---|---|
| PUB-01 | Acceso anónimo a la aplicación pública | `HTTP 200` |
| PUB-02 | La aplicación pública no envía redirección OIDC | No existe `Location` hacia Keycloak |
| PRO-01 | Acceso anónimo a la aplicación protegida | `HTTP 302` hacia el realm `platform` |
| PRO-02 | Credenciales válidas | Login correcto y acceso a la aplicación |
| PRO-03 | Credenciales inválidas | Acceso denegado |
| PRO-04 | Usuario sin rol requerido | `HTTP 403` |
| PRO-05 | Usuario con `platform-user` | `HTTP 200` |
| PRO-06 | Logout | Sesión invalidada y nuevo acceso redirigido a Keycloak |
| TOK-01 | Issuer del token | Coincide con `/realms/platform` |
| TOK-02 | Firma del token | Validable mediante `jwks_uri` |
| TOK-03 | Expiración | Token rechazado después de `exp` |

## Evidencias

Cada prueba guardará:

- código HTTP;
- cabecera `Location` cuando corresponda;
- issuer y claims no sensibles;
- resultado PASS/FAIL;
- fecha, versión de OpenShift y versión de Keycloak.

Nunca se almacenarán contraseñas, client secrets, access tokens ni refresh tokens.

