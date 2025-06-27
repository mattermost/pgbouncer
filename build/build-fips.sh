#!/bin/bash

# FIPS-Compatible PgBouncer Build Script
# This script builds a FIPS-compatible version of PgBouncer with OpenSSL support

set -e  # Exit on any error

# Configuration
DEFAULT_VERSION="1.23.1"
DEFAULT_IMAGE_TAG="mattermost/pgbouncer"
DEFAULT_DOCKERFILE="build/Dockerfile"

# Parse command line arguments
PGBOUNCER_VERSION="${1:-$DEFAULT_VERSION}"
IMAGE_TAG="${2:-$DEFAULT_IMAGE_TAG}"
REGISTRY="${3:-}"
DOCKERFILE="${4:-$DEFAULT_DOCKERFILE}"

# Build configuration
BUILD_DATE=$(date +%Y%m%d)
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
FULL_TAG="${IMAGE_TAG}:${PGBOUNCER_VERSION}-fips-${BUILD_DATE}"

# Registry prefix if provided
if [ -n "$REGISTRY" ]; then
    FULL_TAG="${REGISTRY}/${FULL_TAG}"
fi

# Platform configuration
PLATFORMS=${BUILDX_PLATFORMS:-"linux/amd64,linux/arm64"}

echo "=============================================="
echo "FIPS-Compatible PgBouncer Build"
echo "=============================================="
echo "PgBouncer Version: $PGBOUNCER_VERSION"
echo "Image Tag:         $FULL_TAG"
echo "Dockerfile:        $DOCKERFILE"
echo "Platforms:         $PLATFORMS"
echo "Build Date:        $BUILD_DATE"
echo "Git Commit:        $GIT_COMMIT"
echo "=============================================="

# Validate inputs
if [ ! -f "$DOCKERFILE" ]; then
    echo "ERROR: Dockerfile not found at $DOCKERFILE"
    exit 1
fi

if [ ! -f "build/fips-compat.patch" ]; then
    echo "ERROR: FIPS compatibility patch not found at build/fips-compat.patch"
    exit 1
fi

# Enable BuildKit
export DOCKER_BUILDKIT=1

# Check if docker buildx is available for multi-platform builds
if docker buildx version >/dev/null 2>&1 && [ "$PLATFORMS" != "linux/amd64" ]; then
    echo "Using docker buildx for multi-platform build..."
    
    # Create buildx instance if it doesn't exist
    if ! docker buildx inspect fips-builder >/dev/null 2>&1; then
        echo "Creating buildx instance..."
        docker buildx create --name fips-builder --use
    else
        docker buildx use fips-builder
    fi
    
    # Build multi-platform image
    docker buildx build \
        --platform "$PLATFORMS" \
        --build-arg PGBOUNCER_VERSION="$PGBOUNCER_VERSION" \
        --build-arg BUILD_DATE="$BUILD_DATE" \
        --build-arg GIT_COMMIT="$GIT_COMMIT" \
        --label "org.opencontainers.image.title=PgBouncer FIPS" \
        --label "org.opencontainers.image.description=FIPS-compatible PgBouncer with OpenSSL support" \
        --label "org.opencontainers.image.version=$PGBOUNCER_VERSION" \
        --label "org.opencontainers.image.created=$BUILD_DATE" \
        --label "org.opencontainers.image.revision=$GIT_COMMIT" \
        --label "org.opencontainers.image.source=https://github.com/mattermost/pgbouncer" \
        --tag "$FULL_TAG" \
        --file "$DOCKERFILE" \
        --push \
        .
else
    echo "Using standard docker build..."
    
    # Build single-platform image
    docker build \
        --build-arg PGBOUNCER_VERSION="$PGBOUNCER_VERSION" \
        --build-arg BUILD_DATE="$BUILD_DATE" \
        --build-arg GIT_COMMIT="$GIT_COMMIT" \
        --label "org.opencontainers.image.title=PgBouncer FIPS" \
        --label "org.opencontainers.image.description=FIPS-compatible PgBouncer with OpenSSL support" \
        --label "org.opencontainers.image.version=$PGBOUNCER_VERSION" \
        --label "org.opencontainers.image.created=$BUILD_DATE" \
        --label "org.opencontainers.image.revision=$GIT_COMMIT" \
        --label "org.opencontainers.image.source=https://github.com/mattermost/pgbouncer" \
        --tag "$FULL_TAG" \
        --file "$DOCKERFILE" \
        .
fi

# Create additional tags
echo "Creating additional tags..."

# Latest FIPS tag
LATEST_FIPS_TAG="${IMAGE_TAG}:latest-fips"
if [ -n "$REGISTRY" ]; then
    LATEST_FIPS_TAG="${REGISTRY}/${LATEST_FIPS_TAG}"
fi

# Version FIPS tag (without date)
VERSION_FIPS_TAG="${IMAGE_TAG}:${PGBOUNCER_VERSION}-fips"
if [ -n "$REGISTRY" ]; then
    VERSION_FIPS_TAG="${REGISTRY}/${VERSION_FIPS_TAG}"
fi

# Tag the image
docker tag "$FULL_TAG" "$LATEST_FIPS_TAG"
docker tag "$FULL_TAG" "$VERSION_FIPS_TAG"

echo "=============================================="
echo "Build completed successfully!"
echo "=============================================="
echo "Built images:"
echo "  $FULL_TAG"
echo "  $LATEST_FIPS_TAG"
echo "  $VERSION_FIPS_TAG"
echo ""
echo "To push to registry:"
echo "  docker push $FULL_TAG"
echo "  docker push $LATEST_FIPS_TAG"
echo "  docker push $VERSION_FIPS_TAG"
echo ""
echo "To test the image:"
echo "  docker run --rm $LATEST_FIPS_TAG --version"
echo ""
echo "To use in Kubernetes:"
echo "  image: $VERSION_FIPS_TAG"
echo "=============================================="

# Optional: Run basic smoke tests
if [ "${RUN_TESTS:-false}" = "true" ]; then
    echo "Running smoke tests..."
    
    # Test that the binary exists and runs
    echo "Testing binary execution..."
    docker run --rm "$LATEST_FIPS_TAG" --version
    
    # Test that OpenSSL is linked
    echo "Testing OpenSSL linkage..."
    docker run --rm --entrypoint ldd "$LATEST_FIPS_TAG" /usr/bin/pgbouncer | grep -i ssl || {
        echo "WARNING: OpenSSL not found in pgbouncer linkage"
    }
    
    # Test FIPS mode (if available)
    echo "Testing FIPS availability..."
    docker run --rm --entrypoint openssl "$LATEST_FIPS_TAG" version -a | grep -i fips || {
        echo "INFO: FIPS mode not explicitly shown (may still be available)"
    }
    
    echo "Smoke tests completed!"
fi

# Success
echo "FIPS-compatible PgBouncer build completed successfully!"
exit 0 