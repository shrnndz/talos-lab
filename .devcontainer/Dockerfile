FROM fedora:42@sha256:83ca5776c0a9bc9fad2267a3c355f27f56f08f9acbb1b4e5a8bf751baa46646e

ARG username=shernandez

USER root

COPY .devcontainer/kubernetes.repo /etc/yum.repos.d/

# If this doesn't change much, this layer should rarely need to be rebuilt
RUN dnf update && \ 
    dnf install git zsh awk yq vim ssh just openssl python3 python3-pip -y && \
    useradd ${username} && \
    echo "${username} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

RUN dnf install kubectl -y
RUN curl -sL https://talos.dev/install | sh
RUN curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && \
    chmod 700 get_helm.sh && \
    ./get_helm.sh

USER ${username}
