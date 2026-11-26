
# Stage 1: Get the official Keycloak image
FROM quay.io/keycloak/keycloak:26.8.2-3@sha256:7e66a96e4739239070aeaf72e4c5decf0f7f682cfc725b9f7ea2b336eaba38b3 AS source

# Stage 2: Create a patched base image using UBI 9 Minimal (pinned to a stable version)
FROM registry.access.redhat.com/ubi9/ubi-minimal:9.4@sha256:c0e70387664f30cd9cf2795b547e4a9a51002c44a4a86aa9335ab030134bf392 AS patched_base
USER root
# Fix OS vulnerabilities (glibc, java, etc.) and install Java 17
RUN microdnf update -y && \
    microdnf install -y shadow-utils java-17-openjdk-headless && \
    groupadd -g 1000 keycloak && \
    useradd -u 1000 -g keycloak -m -d /opt/keycloak -s /sbin/nologin keycloak && \
    microdnf remove -y shadow-utils && \
    microdnf clean all

ARG MIN_JAVA_VERSION=17.0.21.1
RUN JAVA_VERSION_FOUND=$(java -XshowSettings:properties -version 2>&1 | sed -n 's/^ *java.version = //p') && \
    printf '%s\n%s\n' "$MIN_JAVA_VERSION" "$JAVA_VERSION_FOUND" | sort -V -C || \
    { echo "Java $JAVA_VERSION_FOUND is older than $MIN_JAVA_VERSION (CVE-2026-114938)"; exit 1; }

# Stage 3: Final Image
FROM patched_base
COPY --from=source --chown=keycloak:keycloak /opt/keycloak/ /opt/keycloak/

# Copy your local configurations/providers
COPY --chown=keycloak:keycloak ./conf/ /opt/keycloak/conf/
COPY --chown=keycloak:keycloak ./providers/ /opt/keycloak/providers/
COPY --chown=keycloak:keycloak ./themes/ /opt/keycloak/themes/
COPY --chown=keycloak:keycloak ./imports/ /opt/keycloak/imports/

USER keycloak

ENV KC_FEATURES=token-exchange
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true
ENV KC_PROXY=edge
ENV KC_HOSTNAME_STRICT=false
ENV KC_HOSTNAME_STRICT_HTTPS=false
ENV KC_HTTP_RELATIVE_PATH=/auth
ENV KC_SPI_LOGIN_PROTOCOL_OPENID_CONNECT_LEGACY_LOGOUT_REDIRECT_URI=true

RUN /opt/keycloak/bin/kc.sh build

EXPOSE 8080
WORKDIR /opt/keycloak

ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
CMD ["start", "--optimized", "--import-realm", "--spi-connections-jpa-legacy-migration-strategy=update", "--spi-login-protocol-openid-connect-suppress-logout-confirmation-screen=true"]