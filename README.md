### Getting machine information

To get disk info;

```bash
talosctl get disks --insecure --nodes $CONTROL_PLANE_IP
```

To get network info:
```bash
talosctl get link --nodes 192.168.20.150
```

### Relevant traefik config

```yaml
# traefik.yml
entryPoints:
  kubernetes:
    address: :6443

---

# conf.yml
tcp:
  routers:
    router0:
      rule: "ClientIP(`192.168.0.0/16`)"
      entryPoints:
      - kubernetes
      service: "kubernetes"
      tls:
        passthrough: true

  services:
    kubernetes:
      loadBalancer:
        servers:
          - address: 192.168.10.150:6443
          - address: 192.168.10.151:6443
```

### Gen A Control Plane Config for A Specific Machine

```bash
talosctl gen config proxmox-cluster https://$CLUSTER_IP:6443 --with-secrets secrets.yaml --output-types controlplane --config-patch @controlplane/control-plane-common.yaml --config-patch-control-plane @controlplane/talos-ctrl-$MACHINE_COUNT.yaml --output temp/talos-ctrl-$MACHINE_COUNT.yaml
```

### Gen a Worker Config

```bash
talosctl gen config proxmox-cluster https://$CLUSTER_IP:6443 --with-secrets secrets.yaml --output-types worker --config-patch @config/control-plane-common.yaml --output temp/worker.yaml
```

### Gen the talosconf

```bash
talosctl gen config proxmox-cluster https://$CLUSTER_IP:6443 --with-secrets secrets.yaml --output-types talosconfig --config-patch @config/control-plane-common.yaml
```

### Install Cilium

```bash
helm install \
    cilium \
    cilium/cilium \
    --version 1.17.2 \
    --namespace kube-system \
    --set ipam.mode=kubernetes \
    --set externalIPs.enabled=true \
    --set kubeProxyReplacement=true \
    --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
    --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
    --set cgroup.autoMount.enabled=false \
    --set cgroup.hostRoot=/sys/fs/cgroup \
    --set devices='{ens+}' \
    --set k8sServiceHost=localhost \
    --set k8sServicePort=7445 \
    --set l2announcements.enabled=true \
    --set l2announcements.leaseDuration=3s \
    --set l2announcements.leaseRenewDeadline=1s \
    --set l2announcements.leaseRetryPeriod=200ms \
    --set k8sClientRateLimit.qps=10 \
    --set k8sClientRateLimit.burst=20 
```

Configure the l2 policies

```yaml
apiVersion: "cilium.io/v2alpha1"
kind: CiliumL2AnnouncementPolicy
metadata:
  name: core
spec:
  #serviceSelector:
    #matchLabels:
      #color: blue
  #nodeSelector:
    #matchExpressions:
      #- key: node-role.kubernetes.io/control-plane
        #operator: DoesNotExist
  interfaces:
  - ^ens[0-9]+
  externalIPs: true
  loadBalancerIPs: true
```