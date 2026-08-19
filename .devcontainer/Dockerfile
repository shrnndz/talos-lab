FROM fedora:42

ARG username=shernandez
ARG KUBELOGIN_VERSION=v1.36.2
ARG OPENBAO_VERSION=2.6.1
ARG TARGETARCH

USER root

COPY .devcontainer/*.repo /etc/yum.repos.d/

# If this doesn't change much, this layer should rarely need to be rebuilt
RUN dnf update -y && \
    dnf install git zsh awk yq vim ssh just openssl tofu python3 python3-pip unzip curl -y && \
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

RUN set -eux; \
    case "${TARGETARCH:-$(uname -m)}" in \
        amd64|x86_64) \
            openbao_arch=amd64; \
            openbao_sha256=ca8d836eb3a5c80407e45e762300b64e7138c419e78826955f2e4ba4ce6d8a6b; \
            ;; \
        arm64|aarch64) \
            openbao_arch=arm64; \
            openbao_sha256=a74aa73b80000a4340a90edbf27726c0fb0a4537970eab6e1a7e0e211d117b75; \
            ;; \
        *) \
            echo "Unsupported OpenBao architecture: ${TARGETARCH:-$(uname -m)}" >&2; \
            exit 1; \
            ;; \
    esac; \
    curl -fsSL -o /tmp/openbao.tar.gz \
        "https://github.com/openbao/openbao/releases/download/v${OPENBAO_VERSION}/openbao_${OPENBAO_VERSION}_linux_${openbao_arch}.tar.gz"; \
    echo "${openbao_sha256}  /tmp/openbao.tar.gz" | sha256sum -c -; \
    mkdir -p /tmp/openbao; \
    tar -xzf /tmp/openbao.tar.gz -C /tmp/openbao; \
    install -m 0755 /tmp/openbao/bao /usr/local/bin/bao; \
    rm -rf /tmp/openbao /tmp/openbao.tar.gz

USER ${username}
