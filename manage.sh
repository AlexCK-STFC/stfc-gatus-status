#!/bin/bash
set -e

### === CONFIG ===
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
ENC_ENV_FILE="$REPO_DIR/enc.env"
DEV_ENC_ENV_FILE="$REPO_DIR/enc.dev.env"
DEC_ENV_FILE="$REPO_DIR/.env.dec"
DOCKER_COMPOSE_FILE="$REPO_DIR/docker-compose.yml"
DEV_DOCKER_COMPOSE_FILE="$REPO_DIR/dev-docker-compose.yml"
DECRYPTED_PREFIX="decrypted-"
CONFIG_SECRET_DIR="$REPO_DIR/config-sops"
CONFIG_DIR="$REPO_DIR/config"
WAIT_TIME=5
MAX_RETRIES=3


### === HELPERS ===
decrypt_env() {
  echo "Decrypting environment variables..."
  sops --decrypt --input-type dotenv --output-type dotenv "$ENC_ENV_FILE" > "$DEC_ENV_FILE"
}

clean_env() {
  if [[ -f "$DEC_ENV_FILE" ]]; then
    echo "Removing decrypted environment file..."
    rm -f "$DEC_ENV_FILE"
  fi
}

docker_up() {
  echo "Starting Docker containers..."
  docker compose -f "$DOCKER_COMPOSE_FILE" --env-file "$DEC_ENV_FILE" up -d --pull always
}

docker_down() {
  echo "Stopping and removing Docker containers..."
  docker compose -f "$DOCKER_COMPOSE_FILE" --env-file "$DEC_ENV_FILE" down
}

decrypt_config_secrets() {
  echo "Decrypting config secrets..."
  shopt -s nullglob
  for file in "$CONFIG_SECRET_DIR"/*.yaml; do
    filename=$(basename "$file")
    decrypted_file="$CONFIG_DIR/$DECRYPTED_PREFIX$filename"
    sops --decrypt "$file" > "$decrypted_file"
    echo " Decrypted $filename -> $decrypted_file"
  done
  shopt -u nullglob
}

clean_decrypted_configs() {
  echo "Cleaning up decrypted config files..."
  rm -f "$CONFIG_DIR/$DECRYPTED_PREFIX"*.yaml
}

wait_for_containers() {
  echo "Waiting for service to report healthy status..."
  sleep 5
  local retries=0

  while (( retries < MAX_RETRIES )); do
    response=$(curl -s http://localhost/health || echo "")
    
    if [[ "$response" == '{"status":"UP"}' ]]; then
      echo "Service is healthy."
      return 0
    else
      echo "Service not healthy yet (response: $response), retrying in $WAIT_TIME seconds... ($((retries+1))/$MAX_RETRIES)"
      sleep "$WAIT_TIME"
      ((retries++))
    fi
  done

  echo "Timeout waiting for service to become healthy."
  echo "=== Docker Compose Logs ==="
  env $(grep -v '^#' "$DEC_ENV_FILE" | xargs) docker compose logs
  return 1
}

### === COMMANDS ===
deploy() {
  cd "$REPO_DIR"

  # Parse optional flags
  local local_flag=false
  local dev_flag=false

  for arg in "$@"; do
    case "$arg" in
      --local) local_flag=true ;;
      --dev) dev_flag=true ;;
    esac
  done

  # Set dev docker compose if requested
  if [[ "$dev_flag" == true ]]; then
    DOCKER_COMPOSE_FILE=$DEV_DOCKER_COMPOSE_FILE
    ENC_ENV_FILE=$DEV_ENC_ENV_FILE
    echo "Using development Docker Compose file: $DOCKER_COMPOSE_FILE"
    echo "Using development env file: $ENC_ENV_FILE"
  fi

  if [[ "$local_flag" == true ]]; then
    echo "Starting local deployment..."
  else
    echo "Starting deployment via GitHub Actions..."
    echo "Pulling latest changes from git..."
    git fetch origin main
    git reset --hard origin/main
  fi

  # Decrypt sensitive files
  clean_decrypted_configs
  decrypt_env
  decrypt_config_secrets

  # Redeploy containers
  echo "Redeploying containers..."
  docker_down
  docker_up

  # Wait and check for container health
  if ! wait_for_containers; then
    echo "Deployment failed: some containers are not healthy."
    clean_env
    clean_decrypted_configs
    exit 1
  fi
  
  # Clean up temporary files
  clean_env
  echo "Deployment successful! ✅"
}

teardown() {
  cd "$REPO_DIR"

  # Parse optional flag
  local dev_flag=false

  for arg in "$@"; do
    case "$arg" in
      --dev) dev_flag=true ;;
    esac
  done

  # Handle --dev flag
  if [[ "$dev_flag" == true ]]; then
    DOCKER_COMPOSE_FILE="$REPO_DIR/dev-docker-compose.yml"
    ENC_ENV_FILE="$REPO_DIR/enc.dev.env"
    echo "Using development Docker Compose file: $DOCKER_COMPOSE_FILE"
    echo "Using development env file: $ENC_ENV_FILE"
  fi

  decrypt_env
  docker_down
  clean_env
  clean_decrypted_configs
  echo "Teardown complete."
}


### === DISPATCH ===
case "$1" in
  deploy) deploy  "$@" ;;
  teardown) teardown "$@" ;;
  *) echo "Usage: $0 deploy [--local] [--dev] | teardown" && exit 1 ;;
esac