apiVersion: v1
kind: Namespace
metadata:
  name: ${APPS_NAMESPACE}
  labels:
    app.kubernetes.io/part-of: keycloak-poc
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-public
  namespace: ${APPS_NAMESPACE}
  labels:
    app: app-public
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app-public
  template:
    metadata:
      labels:
        app: app-public
    spec:
      containers:
        - name: backend
          image: registry.access.redhat.com/ubi9/python-312:latest
          imagePullPolicy: IfNotPresent
          command: ["python"]
          args: ["/opt/app-root/src/app.py"]
          env:
            - name: APP_VARIANT
              value: public
            - name: BIND_ADDRESS
              value: 0.0.0.0
            - name: PORT
              value: "8080"
          ports:
            - name: http
              containerPort: 8080
          readinessProbe:
            httpGet:
              path: /healthz
              port: http
          livenessProbe:
            httpGet:
              path: /healthz
              port: http
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 250m
              memory: 256Mi
          volumeMounts:
            - name: app-source
              mountPath: /opt/app-root/src/app.py
              subPath: app.py
              readOnly: true
      volumes:
        - name: app-source
          configMap:
            name: keycloak-poc-backend
---
apiVersion: v1
kind: Service
metadata:
  name: app-public
  namespace: ${APPS_NAMESPACE}
spec:
  selector:
    app: app-public
  ports:
    - name: http
      port: 8080
      targetPort: http
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: app-public
  namespace: ${APPS_NAMESPACE}
spec:
  host: ${PUBLIC_HOST}
  to:
    kind: Service
    name: app-public
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-protected
  namespace: ${APPS_NAMESPACE}
  labels:
    app: app-protected
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app-protected
  template:
    metadata:
      labels:
        app: app-protected
    spec:
      containers:
        - name: backend
          image: registry.access.redhat.com/ubi9/python-312:latest
          imagePullPolicy: IfNotPresent
          command: ["python"]
          args: ["/opt/app-root/src/app.py"]
          env:
            - name: APP_VARIANT
              value: protected
            - name: BIND_ADDRESS
              value: 127.0.0.1
            - name: PORT
              value: "8080"
          ports:
            - name: backend
              containerPort: 8080
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 250m
              memory: 256Mi
          volumeMounts:
            - name: app-source
              mountPath: /opt/app-root/src/app.py
              subPath: app.py
              readOnly: true
        - name: oauth2-proxy
          image: quay.io/oauth2-proxy/oauth2-proxy:v7.15.2
          imagePullPolicy: IfNotPresent
          args:
            - --provider=keycloak-oidc
            - --oidc-issuer-url=https://${KEYCLOAK_HOST}/realms/platform
            - --redirect-url=https://${PROTECTED_HOST}/oauth2/callback
            - --upstream=http://127.0.0.1:8080/
            - --http-address=0.0.0.0:4180
            - --email-domain=*
            - --allowed-role=platform-user
            - --code-challenge-method=S256
            - --reverse-proxy=true
            - --skip-provider-button=true
            - --skip-jwt-bearer-tokens=true
            - --pass-access-token=true
            - --pass-user-headers=true
            - --set-xauthrequest=true
            - --cookie-secure=true
            - --cookie-samesite=lax
          env:
            - name: OAUTH2_PROXY_CLIENT_ID
              valueFrom:
                secretKeyRef:
                  name: app-protected-oidc
                  key: client-id
            - name: OAUTH2_PROXY_CLIENT_SECRET
              valueFrom:
                secretKeyRef:
                  name: app-protected-oidc
                  key: client-secret
            - name: OAUTH2_PROXY_COOKIE_SECRET
              valueFrom:
                secretKeyRef:
                  name: app-protected-oidc
                  key: cookie-secret
          ports:
            - name: oauth2
              containerPort: 4180
          readinessProbe:
            httpGet:
              path: /ping
              port: oauth2
          livenessProbe:
            httpGet:
              path: /ping
              port: oauth2
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 250m
              memory: 256Mi
      volumes:
        - name: app-source
          configMap:
            name: keycloak-poc-backend
---
apiVersion: v1
kind: Service
metadata:
  name: app-protected
  namespace: ${APPS_NAMESPACE}
spec:
  selector:
    app: app-protected
  ports:
    - name: oauth2
      port: 4180
      targetPort: oauth2
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: app-protected
  namespace: ${APPS_NAMESPACE}
spec:
  host: ${PROTECTED_HOST}
  to:
    kind: Service
    name: app-protected
  port:
    targetPort: oauth2
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect

