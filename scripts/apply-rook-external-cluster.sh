#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 <external-cluster-env-file>" >&2
}

require_var() {
  local name=$1
  if [[ -z "${!name:-}" ]]; then
    echo "missing required variable: $name" >&2
    exit 1
  fi
}

ceph_user_id() {
  local base=$1
  if [[ -n "${CEPHX_KEY_GENERATION:-}" && "${CEPHX_KEY_GENERATION}" != "0" ]]; then
    printf '%s.%s' "$base" "$CEPHX_KEY_GENERATION"
    return
  fi
  printf '%s' "$base"
}


apply_csi_driver_support() {
  local driver=$1

  kubectl -n "$NAMESPACE" apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${driver}-ctrlplugin-sa
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${driver}-nodeplugin-sa
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ${driver}-ctrlplugin-r
rules:
  - apiGroups: ["coordination.k8s.io"]
    resources: ["leases"]
    verbs: ["get", "watch", "list", "delete", "update", "create"]
  - apiGroups: ["csiaddons.openshift.io"]
    resources: ["csiaddonsnodes"]
    verbs: ["get", "watch", "list", "create", "update", "delete"]
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get"]
  - apiGroups: ["apps"]
    resources: ["replicasets"]
    verbs: ["get"]
  - apiGroups: ["apps"]
    resources: ["deployments/finalizers", "daemonsets/finalizers"]
    verbs: ["update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${driver}-ctrlplugin-rb
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: ${driver}-ctrlplugin-r
subjects:
  - kind: ServiceAccount
    name: ${driver}-ctrlplugin-sa
    namespace: ${NAMESPACE}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ${driver}-nodeplugin-r
rules:
  - apiGroups: ["csiaddons.openshift.io"]
    resources: ["csiaddonsnodes"]
    verbs: ["get", "watch", "list", "create", "update", "delete"]
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get"]
  - apiGroups: ["apps"]
    resources: ["replicasets"]
    verbs: ["get"]
  - apiGroups: ["apps"]
    resources: ["deployments/finalizers", "daemonsets/finalizers"]
    verbs: ["update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${driver}-nodeplugin-rb
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: ${driver}-nodeplugin-r
subjects:
  - kind: ServiceAccount
    name: ${driver}-nodeplugin-sa
    namespace: ${NAMESPACE}
EOF

  kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ${driver}-ctrlplugin-cr
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["persistentvolumes"]
    verbs: ["get", "list", "watch", "create", "delete", "patch", "update"]
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["get", "list", "watch", "update"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["list", "watch", "create", "update", "patch"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["volumeattachments"]
    verbs: ["get", "list", "watch", "patch"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["volumeattachments/status"]
    verbs: ["patch"]
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["csinodes"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["persistentvolumeclaims/status"]
    verbs: ["patch"]
  - apiGroups: ["snapshot.storage.k8s.io"]
    resources: ["volumesnapshots", "volumesnapshotclasses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["snapshot.storage.k8s.io"]
    resources: ["volumesnapshotcontents"]
    verbs: ["get", "list", "watch", "patch", "update"]
  - apiGroups: ["snapshot.storage.k8s.io"]
    resources: ["volumesnapshotcontents/status"]
    verbs: ["update", "patch"]
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get"]
  - apiGroups: [""]
    resources: ["serviceaccounts"]
    verbs: ["get"]
  - apiGroups: [""]
    resources: ["serviceaccounts/token"]
    verbs: ["create"]
  - apiGroups: ["groupsnapshot.storage.k8s.io"]
    resources: ["volumegroupsnapshotclasses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["groupsnapshot.storage.k8s.io"]
    resources: ["volumegroupsnapshotcontents"]
    verbs: ["get", "list", "watch", "update", "patch"]
  - apiGroups: ["groupsnapshot.storage.k8s.io"]
    resources: ["volumegroupsnapshotcontents/status"]
    verbs: ["update", "patch"]
  - apiGroups: ["groupsnapshot.storage.openshift.io"]
    resources: ["volumegroupsnapshotclasses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["groupsnapshot.storage.openshift.io"]
    resources: ["volumegroupsnapshotcontents"]
    verbs: ["get", "list", "watch", "update", "patch"]
  - apiGroups: ["groupsnapshot.storage.openshift.io"]
    resources: ["volumegroupsnapshotcontents/status"]
    verbs: ["update", "patch"]
  - apiGroups: ["replication.storage.openshift.io"]
    resources: ["volumegroupreplicationcontents", "volumegroupreplicationclasses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["authentication.k8s.io"]
    resources: ["tokenreviews"]
    verbs: ["create"]
  - apiGroups: ["authorization.k8s.io"]
    resources: ["subjectaccessreviews"]
    verbs: ["create"]
  - apiGroups: ["cbt.storage.k8s.io"]
    resources: ["snapshotmetadataservices"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${driver}-ctrlplugin-crb
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: ${driver}-ctrlplugin-cr
subjects:
  - kind: ServiceAccount
    name: ${driver}-ctrlplugin-sa
    namespace: ${NAMESPACE}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ${driver}-nodeplugin-cr
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["persistentvolumes"]
    verbs: ["get", "list"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["volumeattachments"]
    verbs: ["get", "list"]
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get"]
  - apiGroups: [""]
    resources: ["serviceaccounts"]
    verbs: ["get"]
  - apiGroups: [""]
    resources: ["serviceaccounts/token"]
    verbs: ["create"]
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get"]
  - apiGroups: ["authentication.k8s.io"]
    resources: ["tokenreviews"]
    verbs: ["create"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["list", "watch", "create", "update", "patch"]
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${driver}-nodeplugin-crb
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: ${driver}-nodeplugin-cr
subjects:
  - kind: ServiceAccount
    name: ${driver}-nodeplugin-sa
    namespace: ${NAMESPACE}
EOF
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

ENV_FILE=$1
if [[ ! -f "$ENV_FILE" ]]; then
  echo "env file not found: $ENV_FILE" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

NAMESPACE=${NAMESPACE:-rook-ceph}
ROOK_EXTERNAL_CLUSTER_NAME=${ROOK_EXTERNAL_CLUSTER_NAME:-$NAMESPACE}
ROOK_EXTERNAL_ADMIN_SECRET=${ROOK_EXTERNAL_ADMIN_SECRET:-admin-secret}
ROOK_EXTERNAL_MONITOR_SECRET=${ROOK_EXTERNAL_MONITOR_SECRET:-mon-secret}
ROOK_EXTERNAL_MAPPING=${ROOK_EXTERNAL_MAPPING:-{}}
ROOK_EXTERNAL_MAX_MON_ID=${ROOK_EXTERNAL_MAX_MON_ID:-2}
ROOK_RBD_FEATURES=${ROOK_RBD_FEATURES:-layering}
CSI_DRIVER_NAME_PREFIX=${CSI_DRIVER_NAME_PREFIX:-$NAMESPACE}
RBD_STORAGE_CLASS_NAME=${RBD_STORAGE_CLASS_NAME:-ceph-rbd}
CEPHFS_STORAGE_CLASS_NAME=${CEPHFS_STORAGE_CLASS_NAME:-cephfs}

RBD_PROVISIONER="${CSI_DRIVER_NAME_PREFIX}.rbd.csi.ceph.com"
CEPHFS_PROVISIONER="${CSI_DRIVER_NAME_PREFIX}.cephfs.csi.ceph.com"

require_var ROOK_EXTERNAL_FSID
require_var ROOK_EXTERNAL_USERNAME
require_var ROOK_EXTERNAL_USER_SECRET
require_var ROOK_EXTERNAL_CEPH_MON_DATA

kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"
kubectl apply -f manifests/rook-ceph/cluster-external.yaml

kubectl -n "$NAMESPACE" apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: rook-ceph-mon
type: kubernetes.io/rook
stringData:
  cluster-name: ${ROOK_EXTERNAL_CLUSTER_NAME}
  fsid: ${ROOK_EXTERNAL_FSID}
  admin-secret: ${ROOK_EXTERNAL_ADMIN_SECRET}
  mon-secret: ${ROOK_EXTERNAL_MONITOR_SECRET}
  ceph-username: $(ceph_user_id "${ROOK_EXTERNAL_USERNAME}")
  ceph-secret: ${ROOK_EXTERNAL_USER_SECRET}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: rook-ceph-mon-endpoints
data:
  data: ${ROOK_EXTERNAL_CEPH_MON_DATA}
  mapping: '${ROOK_EXTERNAL_MAPPING}'
  maxMonId: "${ROOK_EXTERNAL_MAX_MON_ID}"
EOF

if [[ -n "${ARGS:-}" ]]; then
  kubectl -n "$NAMESPACE" apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: external-cluster-user-command
data:
  args: ${ARGS@Q}
EOF
fi


# Newer Rook releases install the ceph-csi-operator controller manager, but they do
# not automatically create Driver CRs for external clusters. Without these CRs the
# StorageClasses exist, yet no CSI provisioner pods are launched and PVCs remain in
# ExternalProvisioning forever.
if [[ -n "${RBD_POOL_NAME:-}" || -n "${CEPHFS_FS_NAME:-}" || -n "${CEPHFS_POOL_NAME:-}" ]]; then
  kubectl -n "$NAMESPACE" apply -f - <<EOF
apiVersion: csi.ceph.io/v1
kind: OperatorConfig
metadata:
  name: ceph-csi-operator-config
spec:
  driverSpecDefaults:
    enableMetadata: true
    fsGroupPolicy: File
EOF
fi

if [[ -n "${RBD_POOL_NAME:-}" ]]; then
  apply_csi_driver_support rbd

  kubectl -n "$NAMESPACE" apply -f - <<EOF
apiVersion: csi.ceph.io/v1
kind: Driver
metadata:
  name: ${RBD_PROVISIONER}
spec:
  fsGroupPolicy: File
  nodePlugin:
    updateStrategy:
      type: RollingUpdate
  controllerPlugin: {}
EOF
fi

if [[ -n "${RBD_POOL_NAME:-}" ]]; then
  require_var CSI_RBD_NODE_SECRET
  require_var CSI_RBD_NODE_SECRET_NAME
  require_var CSI_RBD_PROVISIONER_SECRET
  require_var CSI_RBD_PROVISIONER_SECRET_NAME

  kubectl -n "$NAMESPACE" apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: rook-${CSI_RBD_NODE_SECRET_NAME}
type: kubernetes.io/rook
stringData:
  userID: $(ceph_user_id "${CSI_RBD_NODE_SECRET_NAME}")
  userKey: ${CSI_RBD_NODE_SECRET}
---
apiVersion: v1
kind: Secret
metadata:
  name: rook-${CSI_RBD_PROVISIONER_SECRET_NAME}
type: kubernetes.io/rook
stringData:
  userID: $(ceph_user_id "${CSI_RBD_PROVISIONER_SECRET_NAME}")
  userKey: ${CSI_RBD_PROVISIONER_SECRET}
EOF

  if [[ -n "${RBD_METADATA_EC_POOL_NAME:-}" ]]; then
    kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${RBD_STORAGE_CLASS_NAME}
provisioner: ${RBD_PROVISIONER}
parameters:
  clusterID: ${NAMESPACE}
  pool: ${RBD_METADATA_EC_POOL_NAME}
  dataPool: ${RBD_POOL_NAME}
  imageFormat: "2"
  imageFeatures: ${ROOK_RBD_FEATURES}
  csi.storage.k8s.io/provisioner-secret-name: rook-${CSI_RBD_PROVISIONER_SECRET_NAME}
  csi.storage.k8s.io/provisioner-secret-namespace: ${NAMESPACE}
  csi.storage.k8s.io/controller-expand-secret-name: rook-${CSI_RBD_PROVISIONER_SECRET_NAME}
  csi.storage.k8s.io/controller-expand-secret-namespace: ${NAMESPACE}
  csi.storage.k8s.io/node-stage-secret-name: rook-${CSI_RBD_NODE_SECRET_NAME}
  csi.storage.k8s.io/node-stage-secret-namespace: ${NAMESPACE}
  csi.storage.k8s.io/fstype: ext4
allowVolumeExpansion: true
reclaimPolicy: Delete
EOF
  else
    kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${RBD_STORAGE_CLASS_NAME}
provisioner: ${RBD_PROVISIONER}
parameters:
  clusterID: ${NAMESPACE}
  pool: ${RBD_POOL_NAME}
  imageFormat: "2"
  imageFeatures: ${ROOK_RBD_FEATURES}
  csi.storage.k8s.io/provisioner-secret-name: rook-${CSI_RBD_PROVISIONER_SECRET_NAME}
  csi.storage.k8s.io/provisioner-secret-namespace: ${NAMESPACE}
  csi.storage.k8s.io/controller-expand-secret-name: rook-${CSI_RBD_PROVISIONER_SECRET_NAME}
  csi.storage.k8s.io/controller-expand-secret-namespace: ${NAMESPACE}
  csi.storage.k8s.io/node-stage-secret-name: rook-${CSI_RBD_NODE_SECRET_NAME}
  csi.storage.k8s.io/node-stage-secret-namespace: ${NAMESPACE}
  csi.storage.k8s.io/fstype: ext4
allowVolumeExpansion: true
reclaimPolicy: Delete
EOF
  fi
fi

if [[ -n "${CEPHFS_FS_NAME:-}" || -n "${CEPHFS_POOL_NAME:-}" ]]; then
  require_var CEPHFS_FS_NAME
  require_var CEPHFS_POOL_NAME
  require_var CSI_CEPHFS_NODE_SECRET
  require_var CSI_CEPHFS_NODE_SECRET_NAME
  require_var CSI_CEPHFS_PROVISIONER_SECRET
  require_var CSI_CEPHFS_PROVISIONER_SECRET_NAME

  kubectl -n "$NAMESPACE" apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: rook-${CSI_CEPHFS_NODE_SECRET_NAME}
type: kubernetes.io/rook
stringData:
  userID: $(ceph_user_id "${CSI_CEPHFS_NODE_SECRET_NAME}")
  userKey: ${CSI_CEPHFS_NODE_SECRET}
---
apiVersion: v1
kind: Secret
metadata:
  name: rook-${CSI_CEPHFS_PROVISIONER_SECRET_NAME}
type: kubernetes.io/rook
stringData:
  userID: $(ceph_user_id "${CSI_CEPHFS_PROVISIONER_SECRET_NAME}")
  userKey: ${CSI_CEPHFS_PROVISIONER_SECRET}
EOF

  apply_csi_driver_support cephfs

  kubectl -n "$NAMESPACE" apply -f - <<EOF
apiVersion: csi.ceph.io/v1
kind: Driver
metadata:
  name: ${CEPHFS_PROVISIONER}
spec:
  fsGroupPolicy: File
  cephFsClientType: kernel
  nodePlugin:
    updateStrategy:
      type: RollingUpdate
  controllerPlugin: {}
EOF

  kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${CEPHFS_STORAGE_CLASS_NAME}
provisioner: ${CEPHFS_PROVISIONER}
parameters:
  clusterID: ${NAMESPACE}
  fsName: ${CEPHFS_FS_NAME}
  pool: ${CEPHFS_POOL_NAME}
  csi.storage.k8s.io/provisioner-secret-name: rook-${CSI_CEPHFS_PROVISIONER_SECRET_NAME}
  csi.storage.k8s.io/provisioner-secret-namespace: ${NAMESPACE}
  csi.storage.k8s.io/controller-expand-secret-name: rook-${CSI_CEPHFS_PROVISIONER_SECRET_NAME}
  csi.storage.k8s.io/controller-expand-secret-namespace: ${NAMESPACE}
  csi.storage.k8s.io/node-stage-secret-name: rook-${CSI_CEPHFS_NODE_SECRET_NAME}
  csi.storage.k8s.io/node-stage-secret-namespace: ${NAMESPACE}
allowVolumeExpansion: true
reclaimPolicy: Delete
EOF
fi
