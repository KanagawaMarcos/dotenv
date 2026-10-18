#!/usr/bin/env bash
set -Eeuo pipefail

# Version and publish only the encrypted snapshot artifacts. Configuration
# changes and unrelated work in this repository are never included here.
repo_dir="${HOME}/Git/dotenv"
snapshot_path="apps/monica/data"

cd "${repo_dir}"
git add "${snapshot_path}"

if git diff --cached --quiet -- "${snapshot_path}"; then
  exit 0
fi

branch="$(git branch --show-current)"
if [[ -z "${branch}" ]]; then
  echo "The dotfiles repository is not on a branch; refusing to push." >&2
  exit 1
fi

git commit -m "backup(monica): encrypted monthly snapshot" -- "${snapshot_path}"
git push origin "HEAD:${branch}"
