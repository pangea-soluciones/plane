#!/usr/bin/env bash
# Ejecutar EN EL SERVIDOR (EC2/Lightsail) con bash — no compila nada en el servidor, solo pull desde ECR.
#
# Requisitos: Docker + Docker Compose v2.
# Antes: login a ECR (elige una opción):
#   A) Desde tu PC (recomendado, sin AWS en el servidor):
#      aws ecr get-login-password --region us-east-1 | ssh ubuntu@TU_IP \
#        "docker login --username AWS --password-stdin 396608806728.dkr.ecr.us-east-1.amazonaws.com"
#   B) En el servidor con AWS CLI e IAM (access key con ecr:GetAuthorizationToken):
#      aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 396608806728.dkr.ecr.us-east-1.amazonaws.com
#
# Uso:
#   export PLANE_DIR="$HOME/plane"   # opcional
#   bash bootstrap-stack-ecr.sh
#
set -euo pipefail

PLANE_DIR="${PLANE_DIR:-$HOME/plane}"
REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/pangea-soluciones/plane/main}"
ECR_REGISTRY="${ECR_REGISTRY:-396608806728.dkr.ecr.us-east-1.amazonaws.com}"

FLAGS=( -f docker-compose.yml -f docker-compose.ecr-override.yml )

mkdir -p "$PLANE_DIR"
cd "$PLANE_DIR"

echo ">> Descargando compose community + override ECR desde $REPO_RAW ..."
curl -fsSL "$REPO_RAW/deployments/cli/community/docker-compose.yml" -o docker-compose.yml
curl -fsSL "$REPO_RAW/deployments/ec2/docker-compose.ecr-override.yml" -o docker-compose.ecr-override.yml

if [[ ! -f .env ]]; then
  curl -fsSL "$REPO_RAW/deployments/ec2/env.example" -o .env
  echo ""
  echo ">> Se creó .env desde env.example. EDITA .env (APP_DOMAIN, WEB_URL, CORS_ALLOWED_ORIGINS, CERT_EMAIL, SECRET_KEY, etc.) y vuelve a ejecutar este script."
  exit 1
fi

echo ">> Comprobando login ECR (docker credential)..."
if ! docker pull "${ECR_REGISTRY}/plane-api:main" --quiet 2>/dev/null; then
  echo "ERROR: No se puede hacer pull de ECR. Haz docker login primero (ver comentarios arriba)."
  exit 1
fi

echo ">> Pull de imágenes..."
docker compose "${FLAGS[@]}" pull api web worker beat-worker migrator proxy plane-mq plane-minio || docker compose "${FLAGS[@]}" pull

echo ">> Migraciones..."
docker compose "${FLAGS[@]}" run --rm migrator

echo ">> Up servicios..."
docker compose "${FLAGS[@]}" up -d plane-db plane-redis plane-mq plane-minio api worker beat-worker web proxy

echo ">> Estado:"
docker compose "${FLAGS[@]}" ps -a
echo ""
echo "Listo. Proxy en puertos 80/443 del host (LISTEN_HTTP_PORT / LISTEN_HTTPS_PORT en .env)."
