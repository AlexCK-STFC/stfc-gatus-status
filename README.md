# Cloud Status Page (Gatus)
This is a WIP status page built using [Gatus](https://github.com/TwiN/gatus/)

## Usage:
```bash
  ./manage.sh deploy [--local] [--dev]          # Pull latest, decrypt, (re)deploy, cleanup 
  # [--local skips the hard reset to origin/main]
  # [--dev deploys using dev-docker-compose and dev-nginx and enc.dev.env]
  ./manage.sh teardown [--dev]         # Decrypt, docker-compose down, cleanup
```
