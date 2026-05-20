#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [ -f .env ]; then
    set -a
    . ./.env
    set +a
fi

if [ -z "${OASIS_HOST:-}" ]; then
    OASIS_HOST="$(hostname -f 2>/dev/null || hostname)"
fi

: "${OASIS_SCHEME:=http}"
: "${OASIS_BASE_PATH:=/nomad-oasis}"
: "${OASIS_DEPLOYMENT:=institute-test-oasis}"
: "${OASIS_MAINTAINER_EMAIL:=nomad-admin@example.org}"
: "${OASIS_HTTP_PORT:=80}"
: "${NOMAD_IMAGE:=nomad-oasis-local:stable}"
: "${BUILD_NOMAD_IMAGE:=true}"

if [ -z "${NOMAD_SERVICES_API_SECRET:-}" ]; then
    NOMAD_SERVICES_API_SECRET="$(openssl rand -hex 32)"
fi

if [ -z "${DOCKER_GID:-}" ]; then
    DOCKER_GID="$(getent group docker 2>/dev/null | cut -d: -f3 || true)"
    DOCKER_GID="${DOCKER_GID:-991}"
fi

if [ -z "${NORTH_CRYPT_KEY:-}" ]; then
    if command -v openssl >/dev/null 2>&1; then
        NORTH_CRYPT_KEY="$(openssl rand -hex 32)"
    else
        NORTH_CRYPT_KEY="978bfb2e13a8448a253c629d8dd84ff89587f30e635b753153960930cad9d36d"
    fi
fi

OASIS_PUBLIC_URL="${OASIS_SCHEME}://${OASIS_HOST}${OASIS_BASE_PATH}"

export DOCKER_GID NOMAD_IMAGE OASIS_HTTP_PORT NOMAD_SERVICES_API_SECRET BUILD_NOMAD_IMAGE

mkdir -p configs .volumes/fs/tmp .volumes/fs/public .volumes/fs/staging .volumes/fs/north/users .volumes/mongo

if command -v sudo >/dev/null 2>&1 && [ "$(id -u)" -ne 0 ]; then
    sudo chown -R 1000:1000 .volumes/fs
    sudo chmod -R u+rwX,g+rwX .volumes/fs
else
    chown -R 1000:1000 .volumes/fs
    chmod -R u+rwX,g+rwX .volumes/fs
fi

sed \
    -e "s|__OASIS_HOST__|${OASIS_HOST}|g" \
    -e "s|__OASIS_BASE_PATH__|${OASIS_BASE_PATH}|g" \
    -e "s|__OASIS_DEPLOYMENT__|${OASIS_DEPLOYMENT}|g" \
    -e "s|__OASIS_PUBLIC_URL__|${OASIS_PUBLIC_URL}|g" \
    -e "s|__OASIS_MAINTAINER_EMAIL__|${OASIS_MAINTAINER_EMAIL}|g" \
    -e "s|__NORTH_CRYPT_KEY__|${NORTH_CRYPT_KEY}|g" \
    configs/nomad.yaml.template > configs/nomad.yaml

if [ "$BUILD_NOMAD_IMAGE" = "true" ]; then
    if [ ! -f "../../packages/nomad-FAIR/Dockerfile" ]; then
        echo "Cannot build local NOMAD image: ../../packages/nomad-FAIR/Dockerfile not found."
        exit 1
    fi

    echo "Building local NOMAD image: $NOMAD_IMAGE"
    docker build --target dev_package -t "$NOMAD_IMAGE" ../../packages/nomad-FAIR
fi

docker compose pull rabbitmq elastic mongo temporal proxy
docker compose up -d

echo "Waiting for NOMAD app to become healthy. First startup can take 10-15 minutes."
for _ in $(seq 1 120); do
    status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' nomad_oasis_app 2>/dev/null || true)"

    if [ "$status" = "healthy" ]; then
        printf '\nNOMAD Oasis started.\n'
        printf 'Alive endpoint: %s/alive\n' "$OASIS_PUBLIC_URL"
        printf 'GUI: %s/gui/\n' "$OASIS_PUBLIC_URL"
        exit 0
    fi

    if [ "$status" = "exited" ] || [ "$status" = "dead" ]; then
        echo "nomad_oasis_app exited during startup. Recent logs:"
        docker compose logs --tail=120 app || true
        exit 1
    fi

    sleep 10
done

echo "NOMAD app did not become healthy within 20 minutes."
docker compose ps || true
docker compose logs --tail=120 app || true
exit 1
