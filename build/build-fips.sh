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

if [ ! -f "build/postgres_compat_fips.h" ]; then
    echo "ERROR: FIPS compatibility replacement file not found at build/postgres_compat_fips.h"
    exit 1
fi

# Enable BuildKit
export DOCKER_BUILDKIT=1

# Handle dual registry authentication
echo "Setting up registry authentication..."

# Check if Chainguard registry is accessible (skip login if already logged in)
echo "Checking Chainguard registry access..."
if docker manifest inspect cgr.dev/mattermost.com/glibc-openssl-fips:14-dev >/dev/null 2>&1; then
    echo "✅ Chainguard registry accessible (already logged in)"
else
    echo "❌ Cannot access Chainguard registry, attempting login..."
    if [ -n "$CHAINGUARD_USERNAME" ] && [ -n "$CHAINGUARD_PASSWORD" ]; then
        echo "Logging into Chainguard registry..."
        echo "$CHAINGUARD_PASSWORD" | docker login cgr.dev --username "$CHAINGUARD_USERNAME" --password-stdin
    elif [ -n "$CHAINGUARD_TOKEN" ]; then
        echo "Logging into Chainguard registry with token..."
        echo "$CHAINGUARD_TOKEN" | docker login cgr.dev --username _token --password-stdin
    else
        echo "ERROR: Cannot access Chainguard registry and no credentials provided."
        echo "Please either:"
        echo "  1. Login manually: docker login cgr.dev"
        echo "  2. Set environment variables:"
        echo "     export CHAINGUARD_USERNAME=your_username"
        echo "     export CHAINGUARD_PASSWORD=your_password"
        exit 1
    fi
fi

# Check if Docker Hub is accessible for push (skip if just building locally)
if [ -n "$DOCKER_USERNAME" ] && [ -n "$DOCKER_PASSWORD" ]; then
    echo "Attempting Docker Hub login for pushing..."
    if echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin 2>/dev/null; then
        echo "✅ Docker Hub login successful"
        DOCKER_PUSH_ENABLED=true
    else
        echo "❌ Docker Hub login failed - will build locally only"
        echo "   (Check DOCKER_USERNAME and DOCKER_PASSWORD)"
        DOCKER_PUSH_ENABLED=false
    fi
elif [ -n "$DOCKERHUB_TOKEN" ]; then
    echo "Attempting Docker Hub login with token..."
    if echo "$DOCKERHUB_TOKEN" | docker login --username "$DOCKER_USERNAME" --password-stdin 2>/dev/null; then
        echo "✅ Docker Hub login successful"
        DOCKER_PUSH_ENABLED=true
    else
        echo "❌ Docker Hub login failed - will build locally only"
        echo "   (Check DOCKER_USERNAME and DOCKERHUB_TOKEN)"
        DOCKER_PUSH_ENABLED=false
    fi
else
    echo "No Docker Hub credentials provided. Will build locally only."
    DOCKER_PUSH_ENABLED=false
fi

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
    
    # Determine if we should push or load
    if [ "$DOCKER_PUSH_ENABLED" = "true" ]; then
        BUILD_ACTION="--push"
        echo "Building and pushing to registry..."
    else
        BUILD_ACTION="--load"
        echo "Building locally (no push credentials or login failed)..."
        # For local builds, use single platform
        PLATFORMS="linux/amd64"
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
        $BUILD_ACTION \
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

# Create additional tags and push (only if we have push credentials)
if [ "$DOCKER_PUSH_ENABLED" = "true" ]; then
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
    
    # Push additional tags
    echo "Pushing additional tags..."
    docker push "$LATEST_FIPS_TAG"
    docker push "$VERSION_FIPS_TAG"
else
    echo "Skipping additional tag creation (no push access)"
fi

echo "=============================================="
echo "Build completed successfully!"
echo "=============================================="
if [ "$DOCKER_PUSH_ENABLED" = "true" ]; then
    echo "Built and pushed images:"
    echo "  $FULL_TAG"
    echo "  $LATEST_FIPS_TAG"
    echo "  $VERSION_FIPS_TAG"
    echo ""
    echo "Images are now available in the registry!"
else
    echo "Built local image:"
    echo "  $FULL_TAG"
    echo ""
    echo "To push to registry, run with correct credentials:"
    echo "  export DOCKER_USERNAME=your_username"
    echo "  export DOCKER_PASSWORD=your_password"
    echo "  ./build/build-fips.sh $PGBOUNCER_VERSION"
fi
echo ""
echo "To test the image:"
echo "  docker run --rm $FULL_TAG --version"
echo ""
echo "To use in Kubernetes:"
if [ "$DOCKER_PUSH_ENABLED" = "true" ]; then
    echo "  image: $VERSION_FIPS_TAG"
else
    echo "  # First push to registry, then use:"
    echo "  image: $VERSION_FIPS_TAG"
fi
echo "=============================================="
echo ""
echo "USAGE EXAMPLES:"
echo ""
echo "1. Build locally (if already logged in to registries):"
echo "   ./build/build-fips.sh"
echo ""
echo "2. Build with manual registry login:"
echo "   docker login cgr.dev"
echo "   docker login  # for pushing to Docker Hub"
echo "   ./build/build-fips.sh"
echo ""
echo "3. Build with environment variables (if not logged in):"
echo "   export CHAINGUARD_USERNAME=your_cg_user"
echo "   export CHAINGUARD_PASSWORD=your_cg_pass"
echo "   export DOCKER_USERNAME=your_docker_user"
echo "   export DOCKER_PASSWORD=your_docker_pass"
echo "   ./build/build-fips.sh"

# Optional: Run basic smoke tests
if [ "${RUN_TESTS:-false}" = "true" ]; then
    echo "Running smoke tests..."
    
    # Test that the binary exists and runs
    echo "Testing binary execution..."
    docker run --rm "$FULL_TAG" --version
    
    # Test that OpenSSL is linked
    echo "Testing OpenSSL linkage..."
    docker run --rm --entrypoint ldd "$FULL_TAG" /usr/bin/pgbouncer | grep -i ssl || {
        echo "WARNING: OpenSSL not found in pgbouncer linkage"
    }
    
    # Test FIPS mode (if available)
    echo "Testing FIPS availability..."
    docker run --rm --entrypoint openssl "$FULL_TAG" version -a | grep -i fips || {
        echo "INFO: FIPS mode not explicitly shown (may still be available)"
    }
    
    echo "Smoke tests completed!"
fi

# Success
echo "FIPS-compatible PgBouncer build completed successfully!"
exit 0 