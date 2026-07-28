# Aplicaciones de demostración

La POC ejecuta el mismo backend en dos variantes:

| Variante | Exposición | Acceso anónimo |
|---|---|---|
| `app-public` | Route directa al backend | `HTTP 200` |
| `app-protected` | Route hacia OAuth2 Proxy | `HTTP 302` hacia Keycloak |

La variante protegida utiliza OAuth2 Proxy 7.15.2 con el provider `keycloak-oidc`,
Authorization Code + PKCE y autorización por el realm role `platform-user`.

El backend muestra:

- variante desplegada;
- usuario y correo propagados por OAuth2 Proxy;
- presencia de un access token, sin imprimirlo;
- cabeceras no sensibles recibidas.

`scripts/50-configure-poc.sh` crea un cliente confidencial y dos usuarios:

- `poc-authorized`, con `platform-user`;
- `poc-denied`, autenticado pero sin el rol requerido.

Las contraseñas se generan aleatoriamente y sólo se guardan en Secrets del clúster.

