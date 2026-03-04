# Installation

```bash
helm repo add external-secrets https://charts.external-secrets.io
```

```bash
helm install external-secrets \
   external-secrets/external-secrets \
    -n external-secrets \
    --create-namespace \
    --values values.yaml
```

# Links

https://external-secrets.io/latest/provider/hashicorp-vault/#example
https://external-secrets.io/latest/guides/common-k8s-secret-types/