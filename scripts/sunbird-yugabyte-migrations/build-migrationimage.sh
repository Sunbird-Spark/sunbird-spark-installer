#!/bin/bash

# Build script for migration Docker image
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Building migration Docker image..."

# Build the migration image
# Context is this directory, not the repo root -- the Dockerfile's `COPY .`
# would otherwise bake the entire repo checkout (including any local,
# git-ignored secrets a real checkout might have on disk -- tf.sh,
# populated global-values.yaml, terraform state) into the image. Matches
# the real CI build path (.github/workflows/build-push-images.yml), which
# already scopes context to ./scripts/sunbird-yugabyte-migrations.
cd "$SCRIPT_DIR"
docker build -f Dockerfile -t ycqlmigrations:latest "$SCRIPT_DIR"

echo "Migration image built successfully: ycql-migrations:latest"

# Tag with current timestamp for versioning
TIMESTAMP=$(date +%Y%m%d%H%M%S)
docker tag ycql-migrations:latest "ycql-migrations:$TIMESTAMP"

echo "Migration image also tagged as: ycql-migrations:$TIMESTAMP"

echo "To push to registry, run:"
echo "  docker push ycql-migrations:latest"
echo "  docker push ycql-migrations:$TIMESTAMP"
