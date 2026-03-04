# Install OpenBao with CSI Driver

Be sure to follow the prerequisites listed [here](https://openbao.org/docs/platform/k8s/csi/installation/) before running the install command. There should be a values file in this directory with the necessary settings, just run

```bash
helm install openbao openbao/openbao -n openbao --create-namespace --values values.yaml
```

Then make sure to apply the ingress route in `ingressRoute.yaml`

## Configure openbao roles for OIDC

This is assuming oidc was mounted at `keycloak` instead of the default `oidc`

```bash
# https://openbao.org/docs/auth/jwt/#redirect-uris is helpful for the "allowed_redirect_uris" bit

bao write auth/keycloak/role/admin \
  role_type="oidc" \
  user_claim="sub" \
  policies="admin,default" \
  oidc_scopes="profile,email" \
  allowed_redirect_uris="https://bao.cercado.io/v1/auth/keycloak/oidc/callback,https://bao.cercado.io/ui/vault/auth/keycloak/oidc/callback,http://localhost:8250/keycloak/callback"
```

## Extra Configuration

### Namespace
The csi driver needs to mount to the underlying host, which is restriced for any namespace but `kube-system`.
To get around this, we need to appy a privlege label to the namesape:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  labels:
    pod-security.kubernetes.io/enforce: privileged # This will allow the pods within to mount to the host filesystem
  name: openbao
```

This may be a good oppertunity to contribute, as the secret store recommends deploying to `kube-system`: https://secrets-store-csi-driver.sigs.k8s.io/topics/best-practices

### Kubernetes Auth

https://openbao.org/docs/auth/kubernetes/

### CSI Agent
The Agent needs [custom configuration](https://openbao.org/docs/agent-and-proxy/agent/#vault-stanza) as it does not play nice with the ssl cert on the server. We will need to add the `tls_server_name` to override the name 
of the host when connecting:

```sh
vault {
    "address" = "https://openbao.openbao.svc:8200"
    "tls_server_name" = "bao.cercado.io" # This is necessary or we will get certificate errors
}

cache {}

listener "unix" {
    address = "/var/run/vault/agent.sock"
    tls_disable = true
}
```
