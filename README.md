# STFC Status Page (Gatus)
This is a WIP status page built using [Gatus](https://github.com/TwiN/gatus/)

## Usage:
```sh
  ./manage.sh deploy           # Pull latest, decrypt, check for changes, redeploy if needed
  ./manage.sh run-only         # Decrypt and docker-compose up without hash check
  ./manage.sh install-cron     # Add cron job to run deploy every 10 minutes
  ./manage.sh remove-cron      # Remove deploy cron job
  ./manage.sh teardown         # Decrypt and docker-compose down
```