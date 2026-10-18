#!/usr/bin/env bash
set -Eeuo pipefail

systemctl --user start monica.service
exec /etc/profiles/per-user/kanagawamarcos/bin/chromium \
  --app=http://127.0.0.1:8092 \
  --user-data-dir="${HOME}/.local/share/monica/chromium-profile" \
  --class=Monica \
  --no-first-run \
  --no-default-browser-check
