# Talos Lab Handoff: Traefik Telemetry and Dashboard

Date: 2026-08-19  
Repository: `/workspaces/talos-lab`  
Branch: `adding-argocd`

## Operating constraint

The user performs all cluster modifications. The assistant may edit repository files, but must not execute live cluster-mutating commands.

## Completed baseline

- Talos: v1.13.8
- Kubernetes: v1.36.3
- Cilium: v1.20.0
- Gateway API CRDs: v1.6.1
- Secure Boot, UKI boot, and module-signature enforcement are enabled on all four nodes.
- Gateway API migrations were completed for Keycloak, Argo CD, HOAS, OpenObserve, Vikunja, and OpenBao.
- Cercado API routes are intentionally out of scope; they are managed elsewhere.

## Relevant files

- `manifests/traefik/traefik-values.yaml` — Traefik chart values, Gateway provider, dashboard, OTLP logs/metrics/traces, and temporary DEBUG logging.
- `manifests/traefik/telemetry-secret.yaml` — OpenBao SecretStore and ExternalSecret for the OpenObserve Authorization value.
- `manifests/traefik/dashboard.yaml` — dashboard IP allowlist and certificate for `tint.hernanfam.com` and `tint.cercado.io`.
- `manifests/traefik/README.md` — OpenBao setup and secret format.
- `manifests/traefik/ingressRoute.yaml` — legacy dashboard IngressRoute, if still present in the repository or cluster.

The deployed Traefik chart/app is 41.2.0 / v3.7.10. The values currently enable both the Kubernetes Gateway provider and the legacy Kubernetes CRD provider. The dashboard remains enabled through the chart’s `ingressRoute.dashboard` configuration.

## Issue 1: OpenObserve telemetry returns 401

Traefik is reaching the OpenObserve endpoint, but all three exporters report unauthorized responses:

```text
failed to send logs ... /v1/logs: 401 Unauthorized
failed to upload metrics ... /v1/metrics: 401 Unauthorized
traces export ... /v1/traces: 401 Unauthorized
```

The current internal endpoint is the OpenObserve service at:

```text
http://opob.openobserve.svc.cluster.local:5080/api/<organization-id>/v1/{logs,metrics,traces}
```

The actual organization identifier is configured in the repository, but is intentionally not repeated here.

A direct public test using the Authorization value extracted from the Kubernetes Secret and an explicit `stream-name: cercado` header returned HTTP 200. This proves the credential and public OpenObserve organization path can work when the headers are sent explicitly. It does not yet prove that the internal service endpoint accepts the same request or that Traefik is injecting the secret-derived header correctly.

The current values use explicit `valueFrom.secretKeyRef` environment variables for the four Traefik OTLP Authorization settings:

```text
TRAEFIK_ACCESSLOG_OTLP_HTTP_HEADERS_AUTHORIZATION
TRAEFIK_LOG_OTLP_HTTP_HEADERS_AUTHORIZATION
TRAEFIK_METRICS_OTLP_HTTP_HEADERS_AUTHORIZATION
TRAEFIK_TRACING_OTLP_HTTP_HEADERS_AUTHORIZATION
```

The non-sensitive `stream-name: cercado` header is configured statically in each OTLP exporter. The OpenBao value should be exactly `Basic <base64-token>`—without an `Authorization=` prefix and without literal surrounding quote characters.

### First checks for the next session

These are read-only except where explicitly marked:

```bash
kubectl -n traefik get externalsecret traefik-openobserve-otlp \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status} reason={.reason} message={.message}{"\n"}{end}'

kubectl -n traefik get secret traefik-openobserve-otlp -o json |
  jq -r '.data | to_entries[] | "\(.key)=\(.value|length) base64-bytes"'

kubectl -n traefik get deployment traefik -o yaml |
  grep -A5 -B2 'TRAEFIK_.*OTLP_HTTP_HEADERS_AUTHORIZATION'
```

Check whether the decoded value has literal quote characters without printing the credential:

```bash
auth_header="$({
  kubectl -n traefik get secret traefik-openobserve-otlp \
    -o jsonpath='{.data.TRAEFIK_TRACING_OTLP_HTTP_HEADERS_AUTHORIZATION}' |
    base64 -d
} 2>/dev/null)"

printf 'length=%s prefix=%s\n' "${#auth_header}" "${auth_header:0:5}"
case "$auth_header" in
  '"'*'"') echo 'WARNING: value has literal surrounding double quotes' ;;
  Basic\ *) echo 'value starts with Basic and has no detected surrounding quotes' ;;
  *) echo 'WARNING: value does not start with Basic followed by a space' ;;
esac
unset auth_header
```

Test the internal endpoint explicitly, without printing the secret:

```bash
auth_header="$({
  kubectl -n traefik get secret traefik-openobserve-otlp \
    -o jsonpath='{.data.TRAEFIK_TRACING_OTLP_HTTP_HEADERS_AUTHORIZATION}' |
    base64 -d
} 2>/dev/null)"

curl -sS -o /tmp/openobserve-internal-response \
  -w 'HTTP status: %{http_code}\n' \
  -X POST \
  'http://192.168.20.55:5080/api/<organization-id>/v1/traces' \
  -H "Authorization: ${auth_header}" \
  -H 'stream-name: cercado' \
  -H 'Content-Type: application/x-protobuf' \
  --data-binary ''

unset auth_header
```

Interpretation:

- Internal HTTP 200 plus Traefik 401: focus on Traefik’s secret-derived environment variables, especially literal quote characters and whether the deployment was restarted after the Secret changed.
- Internal HTTP 401: the internal endpoint is behaving differently from the public endpoint; compare OpenObserve ingress/service configuration and the exact request headers.

If the ExternalSecret was updated, the user can force a refresh and restart Traefik:

```bash
kubectl -n traefik annotate externalsecret traefik-openobserve-otlp \
  force-sync="$(date +%s)" --overwrite

kubectl -n traefik rollout restart deployment/traefik
kubectl -n traefik rollout status deployment/traefik --timeout=10m
```

Afterward, inspect only fresh exporter errors:

```bash
kubectl -n traefik logs deployment/traefik --since=2m |
  grep -Ei '401|Unauthorized|traces export|failed to upload metrics|failed to send logs' ||
  echo 'No recent telemetry authorization errors'
```

Once telemetry works, change `log.level` in `manifests/traefik/traefik-values.yaml` from `DEBUG` back to `INFO` and have the user apply the Helm change.

## Issue 2: Traefik dashboard returns 403

The dashboard request to `https://tint.cercado.io/` returns HTTP 403. Traefik DEBUG logs identify the cause:

```text
Rejecting IP 10.244.0.109: "10.244.0.109" matched none of the trusted IPs
middlewareName=traefik-dashboard-internal@kubernetescrd
middlewareType=IPAllowLister
```

The current middleware allows only:

```yaml
192.168.20.0/24
```

DNS and service details observed:

- `tint.cercado.io` resolves to `192.168.20.25`.
- Traefik Service LoadBalancer external IP is `192.168.20.25`.
- `externalTrafficPolicy` is currently `Cluster`.
- With `Cluster`, the original client source can be masqueraded before Traefik sees it.

First identify the owner of the observed source address:

```bash
kubectl get pods -A -o wide | grep '10.244.0.109'
```

Potential fixes require a deliberate security choice:

1. Preserve the external client source by setting the Traefik Service `externalTrafficPolicy` to `Local`, then verify traffic still reaches a local Traefik endpoint.
2. If `10.244.0.109` is an expected trusted internal client/proxy, add the narrowly appropriate CIDR or exact address to `dashboard-internal`.

Do not broadly allow `10.244.0.0/16` until the source address is identified and the network trust boundary is understood. The dashboard is intentionally restricted to the internal network and must continue using the valid TLS certificate.

Useful read-only checks:

```bash
kubectl -n traefik get middleware dashboard-internal -o yaml
kubectl -n traefik get svc traefik -o yaml
kubectl -n traefik get ingressroute traefik-dashboard -o yaml
kubectl -n traefik get certificate traefik-dashboard-tls -o yaml
```

## Useful validation after fixes

```bash
kubectl get nodes
kubectl -n traefik get pods -o wide
kubectl get gateway -A
kubectl get httproute -A
curl -skD- https://tint.hernanfam.com/ -o /dev/null
curl -skD- https://tint.cercado.io/ -o /dev/null
```

For Gateway API resources, check the actual condition types rather than relying on a generic wait that may not match the installed kubectl behavior:

```bash
kubectl -n traefik get gateway traefik \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status} reason={.reason} message={.message}{"\n"}{end}'
```

Expected successful Gateway conditions are `Accepted=True` and `Programmed=True`. For HTTPRoutes, inspect `.status.parents[*].conditions[*]` and expect `Accepted=True` and `ResolvedRefs=True`.

## Important security notes

- Never paste the OpenObserve Authorization value into chat, logs, a commit, or this handoff.
- The direct curl tests above deliberately avoid printing the header.
- If the authorization value was ever committed or exposed, rotate it in OpenObserve/OpenBao.
- The `stream-name` value is non-sensitive and remains in the tracked Traefik values file.
