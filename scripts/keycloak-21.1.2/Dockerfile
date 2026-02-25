
# Stage 1: Get the official Keycloak image
FROM quay.io/keycloak/keycloak:21.1.2 AS source

# Stage 2: Create a patched base image using UBI 9 Minimal
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest AS patched_base
USER root
# Fix OS vulnerabilities (glibc, java, etc.) and install Java 17
RUN microdnf update -y && \
    microdnf install -y shadow-utils java-17-openjdk-headless && \
    microdnf clean all

# Create the keycloak user and group (mirrors official image)
RUN groupadd -g 1000 keycloak && \
    useradd -u 1000 -g keycloak -m -d /opt/keycloak -s /sbin/nologin keycloak

# Stage 3: Final Image
FROM patched_base
COPY --from=source /opt/keycloak/ /opt/keycloak/

# Copy your local configurations/providers
COPY ./conf/ /opt/keycloak/conf/
COPY ./providers/ /opt/keycloak/providers/
COPY ./themes/ /opt/keycloak/themes/
COPY ./imports/ /opt/keycloak/imports/

USER root
RUN chown -R keycloak:keycloak /opt/keycloak
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