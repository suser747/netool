#!/usr/bin/env bash
# netool 版本读取与展示（由 main.sh source）

netool_read_main_version() {
  local root="${1:-}"
  local v=""
  if [[ -f "${root}/VERSION" ]]; then
    v="$(head -n1 "${root}/VERSION" | tr -d '[:space:]')"
  fi
  printf '%s' "${v:-2.1}"
}

netool_versions_file() {
  local root="${1:-}"
  if [[ -f "${root}/tools/versions.env" ]]; then
    printf '%s' "${root}/tools/versions.env"
    return 0
  fi
  return 1
}

netool_version_of() {
  local tool_id="$1"
  local root="${2:-}"
  local file line key val
  file="$(netool_versions_file "$root" 2>/dev/null || true)"
  [[ -n "$file" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" ]] || continue
    key="${line%%=*}"
    val="${line#*=}"
    if [[ "$key" == "$tool_id" ]]; then
      printf '%s' "$val"
      return 0
    fi
  done <"$file"
  return 1
}

netool_print_all_versions() {
  local root="${1:-}"
  local file line key val
  local main_v
  main_v="$(netool_read_main_version "$root")"
  printf "netool 懒人工具箱 v%s\n" "$main_v"
  print_divider
  file="$(netool_versions_file "$root")" || { log_warn "未找到 tools/versions.env"; return 1; }
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" ]] || continue
    key="${line%%=*}"
    val="${line#*=}"
    [[ "$key" == "main" ]] && continue
    printf "  %-14s %s\n" "$key" "$val"
  done <"$file"
}
