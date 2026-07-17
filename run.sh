#!/bin/sh
# Run DNASrep with plain `docker run` (no docker compose).
# Handy on hosts without the compose plugin, e.g. GCP Container-Optimized OS
# (where /home is mounted noexec: run this with `bash run.sh`, not `./run.sh`).
#
# Usage:
#   bash run.sh [region]        region = eu (default) | us | jp
#   sudo bash run.sh us         (if docker needs root on this host)
#
# Overridable via env: DNAS_IMAGE, DNAS_TAG, REGEN_CERTS
set -e

REGION="${1:-${REGION:-eu}}"
IMAGE="${DNAS_IMAGE:-ghcr.io/a-blondel/dnasrep}"
TAG="${DNAS_TAG:-latest}"
REGEN_CERTS="${REGEN_CERTS:-true}"

echo "Deploying DNASrep (region=${REGION}, image=${IMAGE}, tag=${TAG})"

docker network create dnas 2>/dev/null || true
docker volume create dnas-certs >/dev/null

# Pull the latest images (docker run alone would reuse a cached :latest)
docker pull "${IMAGE}/web:${TAG}"
docker pull "${IMAGE}/tls:${TAG}"

# Recreate cleanly (idempotent)
docker rm -f dnas-web dnas-tls 2>/dev/null || true

docker run -d --name dnas-web --network dnas --restart unless-stopped \
	--memory 128m "${IMAGE}/web:${TAG}"

docker run -d --name dnas-tls --network dnas --restart unless-stopped \
	--memory 64m -p 443:443 \
	-e REGION="${REGION}" -e REGEN_CERTS="${REGEN_CERTS}" -e BACKEND=web:80 \
	-v dnas-certs:/etc/dnas "${IMAGE}/tls:${TAG}"

echo "Started. Follow logs with: docker logs -f dnas-tls"
