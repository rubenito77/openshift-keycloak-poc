# Aplicaciones de demostración

La POC desplegará el mismo backend en dos variantes para que la comparación sea directa:

| Variante | Route | Comportamiento sin sesión |
|---|---|---|
| Pública | `app-public.<apps-domain>` | Responde `HTTP 200` directamente |
| Protegida | `app-protected.<apps-domain>` | Redirige a Keycloak y no entrega la aplicación |

La aplicación protegida utilizará OpenID Connect Authorization Code Flow con PKCE contra el
realm `platform`. Ambas variantes mostrarán la misma página; la protegida añadirá la identidad,
roles y claims recibidos de Keycloak.

Los manifiestos de las aplicaciones se incorporarán después de validar el cliente OIDC y se
acompañarán con pruebas automáticas positivas y negativas.

