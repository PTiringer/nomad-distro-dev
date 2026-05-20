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
: "${NOMAD_IMAGE:=gitlab-registry.mpcdf.mpg.de/nomad-lab/nomad-fair:latest}"

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

export DOCKER_GID NOMAD_IMAGE OASIS_HTTP_PORT

mkdir -p configs .volumes/fs .volumes/mongo

sed \
    -e "s|__OASIS_HOST__|${OASIS_HOST}|g" \
    -e "s|__OASIS_BASE_PATH__|${OASIS_BASE_PATH}|g" \
    -e "s|__OASIS_DEPLOYMENT__|${OASIS_DEPLOYMENT}|g" \
    -e "s|__OASIS_PUBLIC_URL__|${OASIS_PUBLIC_URL}|g" \
    -e "s|__OASIS_MAINTAINER_EMAIL__|${OASIS_MAINTAINER_EMAIL}|g" \
    -e "s|__NORTH_CRYPT_KEY__|${NORTH_CRYPT_KEY}|g" \
    configs/nomad.yaml.template > configs/nomad.yaml

docker compose pull
docker compose up -d

printf '\nNOMAD Oasis started.\n'
printf 'Alive endpoint: %s/alive\n' "$OASIS_PUBLIC_URL"
printf 'GUI: %s/gui/\n' "$OASIS_PUBLIC_URL"

