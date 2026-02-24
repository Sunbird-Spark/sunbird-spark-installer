# Stage 1: Build the JAR
FROM maven:3.9-eclipse-temurin-11 AS builder

WORKDIR /build

# Clone and build the CDC extension
RUN git clone https://github.com/Sunbird-Knowlg/knowledge-platform-db-extensions.git && \
    cd knowledge-platform-db-extensions && \
    git checkout develop && \
    cd janusgraph-cdc-extension && \
    mvn clean package -DskipTests

# Stage 2: Final JanusGraph image
FROM bitnamilegacy/janusgraph:1.1.0-debian-12-r21

# Copy the built JAR from builder stage
COPY --from=builder /build/knowledge-platform-db-extensions/janusgraph-cdc-extension/target/janusgraph-cdc-extension-*.jar /opt/bitnami/janusgraph/lib/
