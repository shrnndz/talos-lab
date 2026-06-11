FROM fedora:42

ARG username=shernandez
ARG KUBELOGIN_VERSION=v1.36.2
ARG TARGETARCH

USER root

COPY .devcontainer/*.repo /etc/yum.repos.d/

# If this doesn't change much, this layer should rarely need to be rebuilt
RUN dnf update -y && \
    dnf install git zsh awk yq vim ssh just openssl tofu python3 python3-pip unzip -y && \
    useradd ${username} && \
    echo "${username} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

RUN dnf install kubectl -y
RUN set -eux; \
    case "${TARGETARCH:-$(uname -m)}" in \
        amd64|x86_64) \
            kubelogin_arch=amd64; \
            kubelogin_sha256=0f9b35e82469dbf1e1ed7cfa8cbaa27ffde733e18930dbaed590518a58eb11cc; \
            ;; \
        arm64|aarch64) \
            kubelogin_arch=arm64; \
            kubelogin_sha256=ec25ece9a0ccf019dd03041e8e195cd3e3893fdc2a6a2ae35b6464ff954bb40b; \
            ;; \
        arm|armv7l) \
            kubelogin_arch=arm; \
            kubelogin_sha256=a5ee781647cb4fa19791ed11ffd072aec0cf517e720777dac7f9ce4ffc78c8e4; \
            ;; \
        *) \
            echo "Unsupported kubelogin architecture: ${TARGETARCH:-$(uname -m)}" >&2; \
            exit 1; \
            ;; \
    esac; \
    curl -fsSL -o /tmp/kubelogin.zip "https://github.com/int128/kubelogin/releases/download/${KUBELOGIN_VERSION}/kubelogin_linux_${kubelogin_arch}.zip"; \
    echo "${kubelogin_sha256}  /tmp/kubelogin.zip" | sha256sum -c -; \
    unzip /tmp/kubelogin.zip -d /tmp/kubelogin; \
    install -m 0755 /tmp/kubelogin/kubelogin /usr/local/bin/kubelogin; \
    ln -sf /usr/local/bin/kubelogin /usr/local/bin/kubectl-oidc_login; \
    rm -rf /tmp/kubelogin /tmp/kubelogin.zip
RUN curl -sL https://talos.dev/install | sh
RUN curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && \
    chmod 700 get_helm.sh && \
    ./get_helm.sh

USER ${username}
