# Vikunja on Kubernetes

This repository deploys Vikunja to the home Kubernetes cluster with:

- Keycloak/OpenID Connect for authentication
- An external PostgreSQL database
- DigitalOcean Spaces for attachment storage
- OpenBao and External Secrets Operator (ESO) for secret delivery
- Traefik, cert-manager, and external-dns for public HTTPS access

The deployment is intentionally independent of Kubernetes persistent volumes.
The cluster does not currently provide any `StorageClass` resources.

## Current architecture

| Component | Configuration |
| --- | --- |
| Public URL | `https://vikunja.hernanfam.com` |
| Kubernetes namespace | `vikunja` |
| Container | `vikunja/vikunja:2.5.0` |
| Application port | `3456` |
| Ingress | Traefik `IngressRoute`, entry point `websecure` |
| Certificate issuer | `ClusterIssuer/cloudflare-issuer` |
| external-dns target | `tint.cercado.io` |
| Authentication | Keycloak OIDC, provider ID `keycloak` |
| Keycloak issuer | `https://auth.hernanfam.com/realms/<realm>` |
| PostgreSQL | External server, database and user `vikunja` |
| PostgreSQL TLS | Disabled because the current server does not support SSL |
| Attachment storage | Private DigitalOcean Spaces bucket |
| OpenBao | `https://bao.cercado.io` |
| OpenBao auth mount | Existing `kubernetes/` mount |
| OpenBao KV engine | KV v2 at `vikunja/` |
| OpenBao secret | `vikunja/config` |
| ESO API | `external-secrets.io/v1` |

The Kubernetes manifest is expected to be named `vikunja-k8s.yaml`.

## Using AI to repeat or modify this setup

Give the AI this README and the current Kubernetes manifest before asking it to
make changes. Do not give it live passwords, client secrets, access keys, OpenBao
tokens, or Kubernetes Secret values.

Suggested initial prompt:

```text
Read README.md and vikunja-k8s.yaml completely before proposing changes.

This is a working Vikunja deployment. Preserve its architecture unless I
explicitly request a change. Verify current official documentation before
changing Vikunja, External Secrets, OpenBao, Keycloak, Traefik, cert-manager,
or DigitalOcean Spaces configuration.

Do not assume current versions, namespaces, CRD API versions, auth mount paths,
StorageClasses, certificate issuer kinds, database TLS support, or secret paths.
Ask me for command output when a value cannot be established from the files.
Never ask me to paste secret values into chat or commit secrets to Git.
Provide changes as reviewable patches and include validation and rollback steps.
```

Useful discovery commands for a future AI session:

```bash
kubectl version
kubectl get nodes -o wide
kubectl get storageclass
kubectl get crd secretstores.external-secrets.io \
  -o jsonpath='{range .spec.versions[*]}{.name}{" storage="}{.storage}{" served="}{.served}{"\n"}{end}'
kubectl -n vikunja get all,secretstore,externalsecret,certificate,ingressroute
kubectl -n vikunja get deployment vikunja -o yaml
kubectl -n vikunja get secretstore openbao-vikunja -o yaml
kubectl -n vikunja get externalsecret vikunja-secrets -o yaml
```

To show an AI which secret keys exist without exposing their values:

```bash
kubectl -n vikunja get secret vikunja-secrets -o json \
  | jq -r '.data | keys[]'
```

## Prerequisites

The cluster must already have:

- Traefik and its `traefik.io/v1alpha1` CRDs
- cert-manager
- external-dns
- External Secrets Operator with `external-secrets.io/v1`
- Network access to the external PostgreSQL server
- Network access to `https://bao.cercado.io`
- Network access to the DigitalOcean Spaces endpoint
- DNS resolution and HTTPS access to Keycloak

Confirm the relevant CRDs before deployment:

```bash
kubectl get crd \
  ingressroutes.traefik.io \
  certificates.cert-manager.io \
  secretstores.external-secrets.io \
  externalsecrets.external-secrets.io
```

## 1. Provision PostgreSQL

Create a dedicated database and owner on the external PostgreSQL cluster:

```sql
CREATE ROLE vikunja
    LOGIN
    PASSWORD '<generated-password>';

CREATE DATABASE vikunja
    OWNER vikunja
    ENCODING 'UTF8'
    TEMPLATE template0;

REVOKE ALL ON DATABASE vikunja FROM PUBLIC;
GRANT CONNECT, TEMPORARY ON DATABASE vikunja TO vikunja;
```

Vikunja runs its own schema migrations, so the `vikunja` role must own the
database or otherwise have the necessary DDL privileges within it. Do not grant
it access to unrelated databases.

The current PostgreSQL server does not support TLS. The deployment therefore
uses:

```yaml
- name: VIKUNJA_DATABASE_SSLMODE
  value: disable
```

This connection is unencrypted. PostgreSQL must remain reachable only through
the trusted private network and must not be exposed publicly. Change the mode to
`verify-full` and configure the PostgreSQL CA when server-side TLS becomes
available.

Test connectivity from Kubernetes before deploying Vikunja. Avoid placing the
password directly in shell history; use an existing secure mechanism to provide
`PGPASSWORD`.

```bash
kubectl create namespace vikunja \
  --dry-run=client \
  -o yaml \
  | kubectl apply -f -

kubectl -n vikunja run postgres-test \
  --rm -it \
  --restart=Never \
  --image=postgres:18 \
  --env="PGPASSWORD=<temporary-value>" \
  -- psql \
    "host=<postgres-host> port=5432 dbname=vikunja user=vikunja sslmode=disable" \
    -c 'SELECT current_database(), current_user, version();'
```

## 2. Provision DigitalOcean Spaces

Create a private Standard Spaces bucket. Record its bucket name and datacenter
region, for example `nyc3`.

Create a dedicated, limited-access Spaces key with Read/Write/Delete permission
only on this bucket. Do not reuse a full-account Spaces key.

Vikunja is configured with:

```text
VIKUNJA_FILES_TYPE=s3
VIKUNJA_FILES_S3_ENDPOINT=https://<region>.digitaloceanspaces.com
VIKUNJA_FILES_S3_BUCKET=<bucket-name>
VIKUNJA_FILES_S3_REGION=us-east-1
VIKUNJA_FILES_S3_USEPATHSTYLE=false
VIKUNJA_FILES_S3_DISABLESIGNING=false
```

The DigitalOcean datacenter is selected by the endpoint. `us-east-1` is retained
as the S3 client/signing region for DigitalOcean SDK compatibility.

Keep the bucket private. Enable object versioning if attachment recovery is
important.

## 3. Configure Keycloak

Create an OpenID Connect client in the desired realm:

| Setting | Value |
| --- | --- |
| Client ID | `vikunja` |
| Client authentication | On |
| Standard flow | On |
| Direct access grants | Off |
| Root URL | `https://vikunja.hernanfam.com` |
| Home URL | `https://vikunja.hernanfam.com/` |
| Valid redirect URI | `https://vikunja.hernanfam.com/auth/openid/keycloak` |
| Web origin | `https://vikunja.hernanfam.com` |

Copy the generated client secret into OpenBao as described below. Keep the
redirect URI exact; the final path component comes from the Vikunja provider ID
`keycloak`.

The deployment requests the scopes:

```text
openid profile email
```

Local Vikunja authentication remains enabled as a break-glass path, while local
user registration is disabled. Restrict which users may access the Keycloak
client in Keycloak; disabling ordinary Vikunja registration alone is not an
OIDC authorization boundary.

## 4. Configure OpenBao

Authenticate the `bao` CLI with sufficient administrative permissions:

```bash
export BAO_ADDR=https://bao.cercado.io
```

### Create the KV v2 engine

Check whether the target mount already exists:

```bash
bao secrets list -detailed | grep '^vikunja/' || true
```

For a new installation, enable it:

```bash
bao secrets enable -path=vikunja kv-v2
```

### Create the read-only policy

```bash
bao policy write vikunja-read - <<'EOF'
path "vikunja/data/config" {
  capabilities = ["read"]
}
EOF
```

This policy permits reading exactly one KV v2 secret. It does not permit list,
write, update, or delete access.

### Create the Kubernetes auth role

The cluster already has a working OpenBao Kubernetes auth backend mounted at
`kubernetes/`. Reuse that mount; do not create an application-specific auth
backend.

```bash
bao write auth/kubernetes/role/vikunja-external-secrets \
  bound_service_account_names=vikunja-external-secrets \
  bound_service_account_namespaces=vikunja \
  audience=openbao \
  token_policies=vikunja-read \
  token_ttl=1h
```

The role accepts only tokens for the dedicated ServiceAccount in the `vikunja`
namespace and grants only the `vikunja-read` policy.

Verify the policy and role without exposing secrets:

```bash
bao policy read vikunja-read
bao read auth/kubernetes/role/vikunja-external-secrets
```

### Write the application secret

`vikunja/config` contains these properties:

```json
{
  "database-password": "...",
  "service-secret": "...",
  "oidc-client-secret": "...",
  "spaces-access-key": "...",
  "spaces-secret-key": "..."
}
```

Generate the Vikunja service secret with:

```bash
openssl rand -hex 32
```

To keep values out of shell history, prepare the JSON in a permission-restricted
temporary file on a memory-backed filesystem:

```bash
umask 077
vi /dev/shm/vikunja-secrets.json
bao kv put -mount=vikunja config @/dev/shm/vikunja-secrets.json
rm /dev/shm/vikunja-secrets.json
```

Verify only the property names:

```bash
bao kv get -format=json -mount=vikunja config \
  | jq -r '.data.data | keys[]'
```

Expected output:

```text
database-password
oidc-client-secret
service-secret
spaces-access-key
spaces-secret-key
```

## 5. External Secrets mapping

The manifest creates these resources in `vikunja`:

- `ServiceAccount/vikunja-external-secrets`
- `SecretStore/openbao-vikunja`
- `ExternalSecret/vikunja-secrets`

The `SecretStore` connects to `https://bao.cercado.io`, uses KV v2 mount
`vikunja`, authenticates through `kubernetes/`, assumes OpenBao role
`vikunja-external-secrets`, and requests a transient token for the dedicated
ServiceAccount with audience `openbao`.

The mature ESO Vault-compatible provider is used against OpenBao's compatible
API. Reevaluate the first-class ESO OpenBao provider only after verifying the
installed ESO version supports every required Kubernetes-auth feature.

The `ExternalSecret` maps the five properties in `vikunja/config` to a generated
Kubernetes Secret named `vikunja-secrets`. The Deployment references that Secret
but never contains the values itself.

## 6. Configure the manifest

Review every unresolved placeholder:

```bash
rg -n 'CHANGE_ME' vikunja-k8s.yaml
```

Supply only non-secret configuration in Git:

- External PostgreSQL hostname
- Keycloak realm name
- DigitalOcean Spaces region
- DigitalOcean Spaces bucket name

Ensure the PostgreSQL SSL setting matches the currently working server:

```yaml
- name: VIKUNJA_DATABASE_SSLMODE
  value: disable
```

Validate the manifest locally if suitable tools are installed:

```bash
kubectl apply --dry-run=client -f vikunja-k8s.yaml
```

Server-side validation is stronger but requires cluster access:

```bash
kubectl apply --dry-run=server -f vikunja-k8s.yaml
```

## 7. Deploy and verify

Apply the manifest:

```bash
kubectl apply -f vikunja-k8s.yaml
```

Confirm OpenBao authentication and synchronization:

```bash
kubectl -n vikunja get serviceaccount,secretstore,externalsecret
kubectl -n vikunja describe secretstore openbao-vikunja
kubectl -n vikunja describe externalsecret vikunja-secrets
```

Wait for the store and generated secret:

```bash
kubectl -n vikunja wait \
  --for=condition=Ready \
  secretstore/openbao-vikunja \
  --timeout=90s

kubectl -n vikunja wait \
  --for=condition=Ready \
  externalsecret/vikunja-secrets \
  --timeout=90s
```

Verify only the generated key names:

```bash
kubectl -n vikunja get secret vikunja-secrets -o json \
  | jq -r '.data | keys[]'
```

Check the application rollout:

```bash
kubectl -n vikunja rollout status deployment/vikunja
kubectl -n vikunja get pods,service,certificate,ingressroute
kubectl -n vikunja logs deployment/vikunja
```

Verify HTTPS and OIDC:

```bash
curl -I https://vikunja.hernanfam.com/
```

Then use a private browser window to verify:

1. The Keycloak login option appears.
2. Keycloak redirects back to Vikunja successfully.
3. A permitted user is provisioned with the expected name and email.
4. Logout and a second login both work.
5. An attachment can be uploaded and downloaded from the private Spaces bucket.

## Secret rotation

Update OpenBao rather than editing a Kubernetes Secret:

```bash
bao kv patch -mount=vikunja config <property>=<new-value>
```

Avoid putting the real value directly into shell history. Use a protected input
file or another secure CLI input mechanism.

ESO refreshes the Kubernetes Secret periodically. To request an immediate
refresh after rotation:

```bash
kubectl -n vikunja annotate externalsecret vikunja-secrets \
  force-sync="$(date +%s)" \
  --overwrite
```

Environment variables are read when the container starts, so restart Vikunja
after the generated Kubernetes Secret changes:

```bash
kubectl -n vikunja rollout restart deployment/vikunja
kubectl -n vikunja rollout status deployment/vikunja
```

## Upgrades

Do not use the floating `latest` image tag. Before upgrading:

1. Read the release notes between the deployed and target versions.
2. Confirm database migration and rollback implications.
3. Back up PostgreSQL and the Spaces bucket.
4. Pin the exact new image tag in Git.
5. Apply the change and inspect migrations in the logs.
6. Test OIDC, task access, and attachments.

Vikunja runs database migrations during startup. Do not assume that rolling the
container image backward will reverse a database migration.

## Backup and recovery

Both data stores are required for a complete recovery:

- PostgreSQL contains users, projects, tasks, configuration, and attachment
  metadata.
- DigitalOcean Spaces contains attachments and uploaded backgrounds.

Back up both with compatible retention and recovery-point objectives. OpenBao
must also be backed up according to its own disaster-recovery procedure because
it stores the credentials required to reconnect the application.

Do not treat the generated Kubernetes Secret as the authoritative backup; it is
a derived copy managed by ESO.

## Troubleshooting

### `SecretStore` is not ready

```bash
kubectl -n vikunja describe secretstore openbao-vikunja
kubectl -n vikunja get events --sort-by=.lastTimestamp
```

Check:

- `https://bao.cercado.io` resolves and has a publicly trusted certificate.
- The OpenBao auth mount is `kubernetes/`.
- The OpenBao role audience is `openbao`.
- The role binds ServiceAccount `vikunja-external-secrets` in namespace
  `vikunja`.
- The ESO controller can request a transient token for that ServiceAccount.

### `ExternalSecret` reports permission denied

```bash
bao policy read vikunja-read
bao read auth/kubernetes/role/vikunja-external-secrets
bao kv get -mount=vikunja config
```

The KV v2 policy API path must be `vikunja/data/config`, while the ESO
`remoteRef.key` is simply `config` because the store already supplies the mount
and KV version.

### Pod reports that `vikunja-secrets` does not exist

Resolve the `SecretStore` or `ExternalSecret` error first. Once ESO creates the
Secret, Kubernetes should be able to start the pod without changing the
Deployment.

### PostgreSQL reports an SSL negotiation error

The current server does not support TLS. Confirm:

```text
VIKUNJA_DATABASE_SSLMODE=disable
```

Also confirm the database hostname includes the port when it is not the default.

### OIDC login fails

Check:

- `VIKUNJA_SERVICE_PUBLICURL` is exactly
  `https://vikunja.hernanfam.com/`.
- The Keycloak issuer includes the correct realm.
- The Keycloak client ID is `vikunja`.
- The Keycloak redirect URI is exactly
  `https://vikunja.hernanfam.com/auth/openid/keycloak`.
- The ID token supplies the `email` and profile claims.
- The Vikunja pod can reach Keycloak's discovery endpoint.

### Attachment operations fail

Check:

- The Spaces endpoint contains the bucket's actual datacenter region.
- The bucket name is correct.
- The key has Read/Write/Delete permission on that bucket.
- Path-style addressing remains disabled.
- The bucket remains private.

## Security rules

- Never commit credentials, tokens, rendered Kubernetes Secrets, OpenBao data,
  PostgreSQL dumps, or temporary secret JSON files.
- Keep OpenBao policies scoped to exact KV v2 API paths.
- Bind OpenBao Kubernetes roles to exact ServiceAccount names and namespaces.
- Use a dedicated DigitalOcean Spaces key scoped to the Vikunja bucket.
- Keep PostgreSQL private, especially while its connection is unencrypted.
- Preserve a tested break-glass login until Keycloak recovery is well understood.
- Review generated patches before allowing an AI to apply them.
- Ask an AI to cite current primary documentation for security-sensitive or
  version-sensitive changes.

## Primary documentation

- [Vikunja configuration](https://vikunja.io/docs/config-options/)
- [Vikunja OpenID Connect](https://vikunja.io/docs/openid/)
- [Vikunja Keycloak example](https://vikunja.io/docs/openid-example-configurations/)
- [Vikunja backup requirements](https://vikunja.io/docs/what-to-backup/)
- [External Secrets Vault provider](https://external-secrets.io/latest/provider/hashicorp-vault/)
- [External Secrets SecretStore](https://external-secrets.io/latest/api/secretstore/)
- [OpenBao Kubernetes authentication](https://openbao.org/docs/auth/kubernetes/)
- [OpenBao KV v2](https://openbao.org/docs/secrets/kv/kv-v2/)
- [OpenBao policies](https://openbao.org/docs/concepts/policies/)
- [DigitalOcean Spaces S3 SDK configuration](https://docs.digitalocean.com/products/spaces/reference/aws-sdks/)
- [DigitalOcean Spaces access keys](https://docs.digitalocean.com/products/spaces/how-to/manage-access/)
