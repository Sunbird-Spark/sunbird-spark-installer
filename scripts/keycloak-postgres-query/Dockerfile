FROM postgres:18.6-bookworm@sha256:afc7e2d441324c0388fa80c3d24f733b4194a4eb7f47dd8ee2b08eb1a24a647c

USER root

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl jq ca-certificates && \
    curl -LO --proto '=https' --tlsv1.2 "https://dl.k8s.io/release/$(curl -L -s --proto '=https' --tlsv1.2 https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/kubectl && \
    rm -rf /var/lib/apt/lists/*

COPY execute_query.sh /usr/local/bin/execute_query.sh

RUN chmod +x /usr/local/bin/execute_query.sh && \
    useradd --uid 1001 --create-home --home-dir /home/queryrunner queryrunner
WORKDIR /home/queryrunner
USER 1001

ENTRYPOINT []
CMD ["/usr/local/bin/execute_query.sh"]
