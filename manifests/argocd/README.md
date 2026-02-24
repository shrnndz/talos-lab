## Setup the credential template

Argo is going to need credentials to github, which can be generate via the organization settings and then imported via the following command:

```sh
argocd repocreds add https://github.com/cercado-dev --github-app-id <app-id> --github-app-installation-id <install-id> --github-app-private-key-path test.private-key.pem
```

Then we can apply the app-of-app patterns with the following command

```sh
kubectl apply -f manifests/argocd/app-of-apps.yaml
```