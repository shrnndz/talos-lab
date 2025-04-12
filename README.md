
### Set the control plane IP

```bash
CONTROL_PLANE_IP=192.168.0.197
```

### Generate the configs

```bash
talosctl gen config talos-cluster https://$CONTROL_PLANE_IP:6443 --output-dir config
```

### If necessary, get disk information

```bash
talosctl get disks --insecure --nodes $CONTROL_PLANE_IP
```


```bash
export TALOSCONFIG="config/talosconfig"
talosctl config endpoint $CONTROL_PLANE_IP
talosctl config node $CONTROL_PLANE_IP
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

### Gen Control plane

```bash
talosctl gen config talos-proxmox-cluster https://$CONTROL_PLANE_IP:6443 --output-dir config --install-image factory.talos.dev/installer/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515:v1.9.2
```

### Gen A Control Plane Config for A Specific Machine

```bash
talosctl gen config proxmox-cluster https://192.168.10.155:6443 --with-secrets secrets.yaml --output-types controlplane --config-patch @controlplane/control-plane-common.yaml --config-patch-control-plane @controlplane/talos-ctrl-01.yaml --output temp/talos-ctrl-01.yaml
```
