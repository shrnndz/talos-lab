cluster-name := "proxmox-cluster"
kube-api-url := "https://192.168.20.155:6443"
endpoints := "192.168.20.150 192.168.20.151 192.168.20.152"

gen-all: gen-ctrl-configs gen-talos-config gen-kube-config

gen-ctrl-configs:
    ./scripts/gen-config.py {{cluster-name}} {{kube-api-url}}

gen-talos-config:
    talosctl gen config {{cluster-name}} {{kube-api-url}} --with-secrets secrets.yaml --output-types talosconfig --output talosconfig --force
    talosctl config endpoints {{endpoints}} --talosconfig talosconfig

gen-kube-config:
    talosctl kubeconfig . --talosconfig talosconfig --nodes $(echo "{{endpoints}}" | cut -d ' ' -f 1)