#!/bin/bash

# Build script for migration Docker image
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "Building migration Docker image..."

# Build the migration image
cd "$SCRIPT_DIR"
docker build -f Dockerfile -t ycqlmigrations:latest "$REPO_ROOT"

echo "Migration image built successfully: ycql-migrations:latest"

# Tag with current timestamp for versioning
TIMESTAMP=$(date +%Y%m%d%H%M%S)
docker tag ycql-migrations:latest "ycql-migrations:$TIMESTAMP"

echo "Migration image also tagged as: ycql-migrations:$TIMESTAMP"

echo "To push to registry, run:"
echo "  docker push ycql-migrations:latest"
echo "  docker push ycql-migrations:$TIMESTAMP"
