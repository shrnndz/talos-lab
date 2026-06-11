# Rook Ceph External Cluster

This repo uses the supported Rook pattern for an **existing** Ceph cluster: install the
Rook operator in Kubernetes, then import the already-running Ceph cluster in
`external` mode. In this model, Proxmox and Ceph continue managing the storage
daemons, while Kubernetes gets RBD and CephFS dynamic provisioning through the
Ceph CSI drivers that ship with Rook.

## What you need from the existing Ceph cluster

Run these commands from a Proxmox or Ceph admin node where `ceph -s` already works.
That matters because the official Rook export script talks directly to the live Ceph
cluster and creates the least-privilege CephX users for Kubernetes.

### 1. Confirm the cluster is healthy

```bash
ceph -s
ceph health detail
```

Do not proceed until the cluster is healthy enough that you would trust it for new
PVCs. Importing a degraded cluster works technically, but it makes storage debugging
much harder later.

### 2. Identify the RBD pool you want Kubernetes to use

```bash
ceph osd lspools
ceph osd pool ls detail
```

Pick the pool you want for block storage. This becomes `RBD_POOL_NAME`.

For a fresh Kubernetes integration, prefer a **dedicated RBD pool** instead of reusing
the same pool as CephFS. Keeping block and filesystem workloads separate makes pool
capacity, troubleshooting, and future policy changes much easier.

If the pool name contains `.` or `_`, also decide on a clean alias for
`--alias-rbd-data-pool-name`. The official Rook export script needs that when it
creates restricted CephX users.

### 3. Identify the CephFS filesystem and data pool, if you want RWX storage

```bash
ceph fs ls --format json-pretty
ceph fs status
```

From `ceph fs ls`, note:

- `name` -> `CEPHFS_FS_NAME`
- the first entry in `data_pools` (or the one you want) -> `CEPHFS_POOL_NAME`

You only need this if you want CephFS-backed PVCs. If you only want RBD, leave the
CephFS variables empty.

For a fresh Kubernetes integration, prefer a **dedicated CephFS filesystem** with its
own metadata and data pools instead of reusing an existing filesystem that already backs
other workloads.

### 4. Export the Rook import values from the existing Ceph cluster

For this repo, the recommended layout is:

- RBD pool: `k8s_rbd`
- CephFS metadata pool: `k8sfs_metadata`
- CephFS data pool: `k8sfs_data`
- CephFS filesystem name: `k8sfs`

Fetch the current official helper script from Rook:

```bash
curl -L \
  https://raw.githubusercontent.com/rook/rook/master/deploy/examples/create-external-cluster-resources.py \
  -o /tmp/create-external-cluster-resources.py
```

Then run it against the existing cluster and save the output to a local, untracked env file:

```bash
mkdir -p .secrets

python3 /tmp/create-external-cluster-resources.py \
  --format bash \
  --namespace rook-ceph \
  --skip-monitoring-endpoint \
  --restricted-auth-permission true \
  --k8s-cluster-name hernanfam \
  --rbd-data-pool-name k8s_rbd \
  --alias-rbd-data-pool-name k8s-rbd \
  --cephfs-filesystem-name k8sfs \
  --cephfs-data-pool-name k8sfs_data \
  > .secrets/rook-external.env
```

If you are only enabling RBD, omit the `--cephfs-*` flags.

If your Ceph manager does not have the Prometheus module enabled yet, keep
`--skip-monitoring-endpoint`. This is a supported path and does not block RBD or CephFS
provisioning. You can enable Ceph mgr Prometheus metrics later and re-run the export if
you want the monitoring endpoint values populated.

If the RBD pool name contains `.` or `_`, add:

```bash
  --alias-rbd-data-pool-name <safe-alias> \
```

If your RBD pool is erasure-coded, also add:

```bash
  --rbd-metadata-ec-pool-name <replicated-rbd-metadata-pool> \
```

The script output should populate values such as:

- `ROOK_EXTERNAL_FSID`
- `ROOK_EXTERNAL_CEPH_MON_DATA`
- `ROOK_EXTERNAL_USERNAME`
- `ROOK_EXTERNAL_USER_SECRET`
- `CSI_RBD_*`
- `CSI_CEPHFS_*` if CephFS was requested

After that, compare the exported file to
[`external-cluster.env.example`](./external-cluster.env.example) and fill in the small
repo-specific defaults that are not secret, like storage class names if you want to
rename them.

## Kubernetes-side deployment

### 1. Install the Rook operator

Pin a chart version intentionally instead of floating to latest:

```bash
helm repo add rook-release https://charts.rook.io/release
helm repo update

helm upgrade --install rook-ceph rook-release/rook-ceph \
  --namespace rook-ceph \
  --create-namespace \
  --version <pin-a-version> \
  --values manifests/rook-ceph/operator-values.yaml
```

This repo keeps only a small values file because the storage daemons stay outside the
cluster. We disable the discovery daemon and keep the operator scoped to its own
namespace.

### 2. Apply the external CephCluster manifest

```bash
kubectl apply -f manifests/rook-ceph/cluster-external.yaml
```

### 3. Import the generated Ceph connection data and create StorageClasses

```bash
./scripts/apply-rook-external-cluster.sh .secrets/rook-external.env
```

That script creates:

- `rook-ceph-mon` secret
- `rook-ceph-mon-endpoints` configmap
- `external-cluster-user-command` configmap when `ARGS` is set
- `ceph-csi-operator-config`, plus the CSI `Driver` resources and driver SAs/RBAC needed by newer Rook releases
- `rook-csi-rbd-node` and `rook-csi-rbd-provisioner` style secrets
- `ceph-rbd` storage class, or your renamed equivalent
- `cephfs` storage class if CephFS values were exported

## Validation

Check the external cluster import:

```bash
kubectl -n rook-ceph get cephcluster
kubectl -n rook-ceph describe cephcluster rook-ceph-external
kubectl -n rook-ceph get secret,configmap
kubectl get storageclass
```

Then create a small PVC and Pod for each storage class you plan to use.

For RBD:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-rbd
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: ceph-rbd
```

For CephFS:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-cephfs
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
  storageClassName: cephfs
```

## Repeatable workflow summary

1. Create or pick a dedicated RBD pool and optional dedicated CephFS filesystem from the existing Ceph cluster.
2. Re-run the official Rook export script from a Ceph admin node.
3. Save the output into `.secrets/rook-external.env`.
4. Install or upgrade the Rook operator with `operator-values.yaml`.
5. Apply `cluster-external.yaml`.
6. Run `./scripts/apply-rook-external-cluster.sh .secrets/rook-external.env`.
7. Validate with a test PVC.

## Notes

- `ROOK_EXTERNAL_MAX_MON_ID` defaults to `2`, which matches a three-monitor cluster
  named `a`, `b`, and `c`. If your monitor set is larger, raise that value in the env file.
- `--skip-monitoring-endpoint` is fine for bootstrap if the Ceph mgr Prometheus module is
  not enabled yet. Rook external mode and Ceph CSI volume provisioning do not require it.
- Keep `.secrets/rook-external.env` out of git. The repo already ignores `.secrets/`.
- This workflow intentionally uses the official Rook export script to create the CephX
  users instead of manually copying admin credentials into Kubernetes.
- On newer Rook releases, the ceph-csi-operator controller manager may be installed without
  the CSI `Driver` custom resources or the driver service accounts/RBAC. If `kubectl -n rook-ceph get
  driver.csi.ceph.io` returns an empty list, or CSI driver pods fail with missing `*-ctrlplugin-sa`
  or `*-nodeplugin-sa` accounts, rerun `./scripts/apply-rook-external-cluster.sh .secrets/rook-external.env`.

## References

- Rook external cluster example:
  https://github.com/rook/rook/blob/master/deploy/examples/cluster-external.yaml
- Rook import helper:
  https://github.com/rook/rook/blob/master/deploy/examples/import-external-cluster.sh
- Rook export helper:
  https://github.com/rook/rook/blob/master/deploy/examples/create-external-cluster-resources.py
