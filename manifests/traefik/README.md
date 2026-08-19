# Traefik telemetry

Traefik exports traces, metrics, internal logs, and access logs to the
OpenObserve OTLP/HTTP endpoints through the in-cluster `opob` Service.

The OpenObserve authorization value is intentionally not stored in Git. It is
read from OpenBao by `ExternalSecret/traefik-openobserve-otlp`.

## OpenBao setup

Run these commands from an authenticated OpenBao administration session. Do
not commit the authorization value or place it in a shell command that will be
saved in history.

Enable the dedicated KV mount if it does not already exist:

```bash
bao secrets enable -path=traefik kv-v2
```

Create a policy that can read only the telemetry credential:

```bash
bao policy write traefik-openobserve-read - <<'EOF'
path "traefik/data/config" {
  capabilities = ["read"]
}
EOF
```

Bind that policy to the Kubernetes ServiceAccount used by External Secrets:

```bash
bao write auth/kubernetes/role/traefik-external-secrets \
  bound_service_account_names=traefik-external-secrets \
  bound_service_account_namespaces=traefik \
  audience=openbao \
  token_policies=traefik-openobserve-read \
  token_ttl=1h
```

Store one property named `authorization` in `traefik/config`. Its value must
be only the value after `Authorization=`, such as `Basic <base64-token>`.
The non-sensitive `stream-name` is configured in the Traefik values file.

```bash
umask 077
vi /dev/shm/traefik-openobserve.json
bao kv put -mount=traefik config @/dev/shm/traefik-openobserve.json
rm /dev/shm/traefik-openobserve.json
```

The temporary JSON should contain:

```json
{
  "authorization": "Basic <base64-token>"
}
```

The Kubernetes resources are defined in `telemetry-secret.yaml`. Its target
uses `creationPolicy: Orphan`, so it can populate the temporary Secret created
during the initial Traefik OTLP setup and will not delete the credential if the
ExternalSecret manifest is later removed. Apply the file before upgrading the
Traefik Helm release so the referenced Secret exists when the new pod starts.

The resulting Kubernetes Secret contains one key named
`OPENOBSERVE_OTLP_AUTHORIZATION`. The Traefik chart renders its static
configuration as CLI arguments, so `traefik-values.yaml` uses Kubernetes
`$(OPENOBSERVE_OTLP_AUTHORIZATION)` argument expansion to add the header to all
four OTLP exporters. Do not rename the key with a `TRAEFIK_` prefix: Traefik
does not support mixing environment-variable and CLI static configuration.

Keep the general Traefik log level at `INFO` when this mechanism is deployed.
At `DEBUG`, Traefik logs its loaded static configuration, which includes OTLP
headers and can disclose the authorization value.
