#!/usr/bin/env bash
set -Eeuo pipefail

# Create a portable, encrypted snapshot inside the dotfiles checkout. No
# plaintext database dump or application storage is written to that checkout.
repo_dir="${HOME}/Git/dotenv"
monica_dir="${HOME}/.local/share/monica"
data_dir="${repo_dir}/apps/monica/data"
recipient_file="${repo_dir}/apps/monica/backup-recipient.txt"
docker_bin="/etc/profiles/per-user/kanagawamarcos/bin/docker"
age_bin="${HOME}/.nix-profile/bin/age"

if [[ ! -x "${age_bin}" ]]; then
  age_bin="$(command -v age)"
fi

if [[ ! -x "${age_bin}" ]]; then
  echo "age is required; install it before backing up Monica." >&2
  exit 1
fi

if [[ ! -f "${recipient_file}" || ! -f "${monica_dir}/.env" ]]; then
  echo "Monica backup configuration is incomplete." >&2
  exit 1
fi

mkdir -p "${data_dir}"
chmod 700 "${data_dir}"

encrypt_to() {
  local target="$1"
  local temporary
  temporary="$(mktemp "${target}.tmp.XXXXXX")"

  "${age_bin}" -R "${recipient_file}" -o "${temporary}"
  mv "${temporary}" "${target}"
}

compose=("${docker_bin}" compose --project-name monica)
app_id="$("${compose[@]}" ps -q app)"

if [[ -z "${app_id}" ]]; then
  echo "Monica application container is not running." >&2
  exit 1
fi

# Transactional MariaDB dump, compressed and encrypted while streaming.
"${compose[@]}" exec -T db sh -c \
  'exec env MYSQL_PWD="$MYSQL_PASSWORD" mariadb-dump -u"$MYSQL_USER" --single-transaction --routines --events "$MYSQL_DATABASE"' \
  | gzip -9 \
  | encrypt_to "${data_dir}/database.sql.gz.age"

# Includes uploaded files and the OAuth keys kept in Monica's storage volume.
"${docker_bin}" cp "${app_id}:/var/www/html/storage" - \
  | gzip -9 \
  | encrypt_to "${data_dir}/storage.tar.gz.age"

# APP_KEY must accompany the database to restore encrypted application values.
"${age_bin}" -R "${recipient_file}" -o "${data_dir}/runtime.env.age.tmp" "${monica_dir}/.env"
mv "${data_dir}/runtime.env.age.tmp" "${data_dir}/runtime.env.age"
