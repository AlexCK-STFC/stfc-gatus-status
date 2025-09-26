# STFC Status Page (Gatus)
This is a WIP status page built using [Gatus](https://github.com/TwiN/gatus/)

## Usage:
```sh
  ./manage.sh deploy [--dev]           # Pull latest, decrypt, (re)deploy, cleanup [--dev skips the pull]
  ./manage.sh teardown         # Decrypt, docker-compose down, cleanup
```