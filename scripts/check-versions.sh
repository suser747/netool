#!/usr/bin/env bash
# 校验各脚本 SCRIPT_VERSION 与 tools/versions.env 是否一致
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT}/tools/versions.env"
fail=0

lookup_expected() {
  local key="$1"
  grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '[:space:]'
}

check_script() {
  local file="$1" key="$2"
  local ver exp
  ver="$(grep -m1 '^SCRIPT_VERSION=' "$file" 2>/dev/null | cut -d= -f2- | tr -d '"'"'"'[:space:]')"
  [[ -n "$ver" ]] || return 0
  exp="$(lookup_expected "$key")"
  [[ -z "$exp" ]] && return 0
  if [[ "$ver" != "$exp" ]]; then
    printf 'MISMATCH %s: script=%s env=%s\n' "$key" "$ver" "$exp"
    fail=1
  fi
}

# main.sh 版本来自 VERSION 文件，见下方校验

while IFS= read -r -d '' f; do
  base="$(basename "$f" .sh)"
  case "$base" in
    common|load_common|version) continue ;;
    disk_full_rw_test) key=disk-test ;;
    disk_slot_map) key=slot-map ;;
    wipe_except_sda_v2) key=wipe ;;
    ssh-port) key=ssh ;;
    app-config) key=app-config ;;
    cron-templates) key=cron-templates ;;
    *) key="$base" ;;
  esac
  check_script "$f" "$key"
done < <(find "${ROOT}/tools" -name '*.sh' -print0)

main_ver="$(head -n1 "${ROOT}/VERSION" 2>/dev/null | tr -d '[:space:]')"
exp_main="$(lookup_expected main)"
if [[ -n "$main_ver" && -n "$exp_main" && "$main_ver" != "$exp_main" ]]; then
  printf 'MISMATCH main: VERSION=%s env=%s\n' "$main_ver" "$exp_main"
  fail=1
fi

if (( fail == 0 )); then
  echo "版本校验通过"
else
  exit 1
fi
