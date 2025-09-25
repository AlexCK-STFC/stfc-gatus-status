#!/bin/bash
set -e

### === CONFIG ===
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
ENC_ENV_FILE="$REPO_DIR/enc.env"
DEC_ENV_FILE="$REPO_DIR/.env.dec"
DOCKER_COMPOSE_FILE="$REPO_DIR/docker-compose.yml"
HASH_FILE="$REPO_DIR/.last_deploy_hash"
SCRIPT_PATH="$REPO_DIR/$(basename "$0")"
CRON_LOG="$REPO_DIR/cron.log"
CRON_SCHEDULE="*/10 * * * *"
CRON_CMD="cd $REPO_DIR && $SCRIPT_PATH deploy >> $CRON_LOG 2>&1"
DECRYPTED_PREFIX="decrypted-"
CONFIG_SECRET_DIR="$REPO_DIR/config-sops"
CONFIG_DIR="$REPO_DIR/config"

### === HELP ===
usage() {
  echo "Usage:"
  echo "  $0 deploy           # Pull latest, decrypt, check for changes, redeploy if needed"
  echo "  $0 run-only         # Decrypt and docker-compose up without hash check"
  echo "  $0 install-cron     # Add cron job to run deploy every 10 minutes"
  echo "  $0 remove-cron      # Remove deploy cron job"
  echo "  $0 teardown         # Decrypt and docker-compose down"
  exit 1
}

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

get_current_hash() {
  cat "$DOCKER_COMPOSE_FILE" "$DEC_ENV_FILE" | sha256sum | cut -d' ' -f1
}

docker_up() {
  echo "Starting Docker containers..."
  docker compose --env-file "$DEC_ENV_FILE" up -d
}

docker_down() {
  echo "Stopping and removing Docker containers..."
  docker compose --env-file "$DEC_ENV_FILE" down
}

cron_install() {
  echo "Adding cron job..."
  (crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" ; echo "$CRON_SCHEDULE $CRON_CMD") | crontab -
  echo "Cron job installed to run every 10 minutes."
}

cron_remove() {
  echo "Removing cron job..."
  crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" | crontab -
  echo "Cron job removed."
}

should_update_repo() {
  echo "Fetching latest changes..."
  git fetch origin main >/dev/null 2>&1

  LOCAL_HASH=$(git rev-parse HEAD)
  REMOTE_HASH=$(git rev-parse origin/main)

  if [[ "$LOCAL_HASH" != "$REMOTE_HASH" ]]; then
    echo "New commit detected: $REMOTE_HASH"
    return 0  # Repo has changed
  else
    echo "No new commits. Skipping deploy."
    return 1  # No changes
  fi
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

### === COMMANDS ===

deploy() {
  cd "$REPO_DIR"

  if ! should_update_repo; then
    exit 0
  fi

  echo "Cleaning up old decrypted configs before pulling..."
  clean_decrypted_configs

  echo "Pulling latest changes from git..."
  git pull origin main

  decrypt_env
  decrypt_config_secrets

  CURRENT_HASH=$(get_current_hash)
  LAST_HASH=""
  if [[ -f "$HASH_FILE" ]]; then
    LAST_HASH=$(cat "$HASH_FILE")
  fi

  if [[ "$CURRENT_HASH" != "$LAST_HASH" ]]; then
    echo "Changes to compose detected, redeploying..."
    docker_down
    docker_up
    echo "$CURRENT_HASH" > "$HASH_FILE"
  else
    echo "No changes to compose detected, skipping redeploy."
  fi

  clean_env
}

run_only() {
  cd "$REPO_DIR"

  echo "Running without compose hash check: decrypting and starting containers..."
  clean_decrypted_configs
  decrypt_env
  decrypt_config_secrets
  docker_up
  clean_env
}

teardown() {
  cd "$REPO_DIR"

  decrypt_env
  docker_down
  clean_env
  clean_decrypted_configs

  if [[ -f "$HASH_FILE" ]]; then
    echo "Removing saved hash file..."
    rm -f "$HASH_FILE"
  fi

  echo "Teardown complete."
}

### === DISPATCH ===

case "$1" in
  deploy) deploy ;;
  run-only) run_only ;;
  install-cron) cron_install ;;
  remove-cron) cron_remove ;;
  teardown) teardown ;;
  *) usage ;;
esac
