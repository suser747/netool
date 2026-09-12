#!/usr/bin/env bash
# netool - 数据库状态与配置查看 (MySQL/MariaDB, PostgreSQL, Redis)
set -Eeuo pipefail

SCRIPT_NAME="db-tools"
SCRIPT_VERSION="1.0"

# shellcheck source=../load_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
trap on_error ERR

usage() {
  cat <<EOF
netool | 数据库工具 v${SCRIPT_VERSION}

用法: db [操作] [类型]

操作:
  status                  探测常见数据库服务
  config mysql|mariadb    MySQL/MariaDB 关键配置（不回显密码）
  config postgres         PostgreSQL 关键配置
  config redis            Redis 关键配置
  connect-test [类型]     连接探测（mysql/postgres/redis，默认全部）

说明: 只读；不读取 ~/.my.cnf 密码内容。
EOF
}

print_banner() {
  [[ -n "${NETOOL:-}" ]] && return 0
  print_divider
  printf "netool | 数据库 v%s\n" "$SCRIPT_VERSION"
  print_divider
}

_db_running() {
  local u="$1"
  systemctl is-active "$u" 2>/dev/null || echo unknown
}

do_status() {
  printf "\n%s数据库服务:%s\n" "$COLOR_BOLD" "$COLOR_RESET"
  local item u
  for item in "mysql:mysql mariadb" "postgres:postgresql postgresql@*" "redis:redis redis-server"; do
    local label="${item%%:*}"
    local units="${item#*:}"
    local found=0
    for u in $units; do
      if systemctl list-unit-files "${u}.service" &>/dev/null 2>&1; then
        found=1
        printf "  %-10s 服务:%s\n" "$label" "$(_db_running "$u")"
      fi
    done
    (( found == 0 )) && command_exists "$label" && printf "  %-10s  命令存在（无 systemd 单元）\n" "$label"
  done
  command_exists mysql && printf "  mysql 客户端: 有\n" || true
  command_exists psql && printf "  psql 客户端: 有\n" || true
  command_exists redis-cli && printf "  redis-cli: 有\n" || true
}

_grep_conf() {
  local file="$1"
  shift
  [[ -r "$file" ]] || return 0
  printf "  [%s]\n" "$file"
  grep -E "$@" "$file" 2>/dev/null | grep -vi password | head -n 20 | sed 's/^/    /' || true
}

do_config_mysql() {
  printf "\n%sMySQL/MariaDB 配置:%s\n" "$COLOR_BOLD" "$COLOR_RESET"
  local f
  for f in /etc/my.cnf /etc/mysql/my.cnf /etc/mysql/mysql.conf.d/mysqld.cnf; do
    _grep_conf "$f" '^(bind-address|datadir|port|socket|log_bin|max_connections)'
  done
}

do_config_postgres() {
  printf "\n%sPostgreSQL 配置:%s\n" "$COLOR_BOLD" "$COLOR_RESET"
  local f
  for f in /etc/postgresql/*/main/postgresql.conf /var/lib/pgsql/data/postgresql.conf; do
    [[ -e "$f" ]] || continue
    _grep_conf "$f" '^(port|listen_addresses|data_directory|max_connections)'
  done
  for f in /etc/postgresql/*/main/pg_hba.conf /var/lib/pgsql/data/pg_hba.conf; do
    [[ -r "$f" ]] && printf "  [%s] (%s 行)\n" "$f" "$(wc -l <"$f" 2>/dev/null || echo 0)"
  done
}

do_config_redis() {
  printf "\n%sRedis 配置:%s\n" "$COLOR_BOLD" "$COLOR_RESET"
  local f
  for f in /etc/redis/redis.conf /etc/redis.conf /usr/local/etc/redis.conf; do
    [[ -r "$f" ]] || continue
    printf "  [%s]\n" "$f"
    grep -E '^(bind |port |dir |requirepass|protected-mode)' "$f" 2>/dev/null | sed 's/requirepass .*/requirepass (已设置)/' | sed 's/^/    /' || true
  done
}

do_connect_test() {
  local which="${1:-all}"
  printf "\n%s连接探测:%s\n" "$COLOR_BOLD" "$COLOR_RESET"
  if [[ "$which" == all || "$which" == mysql || "$which" == mariadb ]]; then
    if command_exists mysqladmin; then
      mysqladmin ping 2>/dev/null && printf "  MySQL: ping OK\n" || printf "  MySQL: ping 失败（可能未运行或无权限）\n"
    else
      printf "  MySQL: 无 mysqladmin\n"
    fi
  fi
  if [[ "$which" == all || "$which" == postgres || "$which" == postgresql ]]; then
    if command_exists pg_isready; then
      pg_isready 2>/dev/null && printf "  PostgreSQL: ready\n" || printf "  PostgreSQL: 未就绪\n"
    else
      printf "  PostgreSQL: 无 pg_isready\n"
    fi
  fi
  if [[ "$which" == all || "$which" == redis ]]; then
    if command_exists redis-cli; then
      redis-cli ping 2>/dev/null | grep -q PONG && printf "  Redis: PONG\n" || printf "  Redis: 无响应\n"
    else
      printf "  Redis: 无 redis-cli\n"
    fi
  fi
}

run_action() {
  case "${1:-status}" in
    status) do_status ;;
    config)
      case "${2:-}" in
        mysql|mariadb) do_config_mysql ;;
        postgres|postgresql) do_config_postgres ;;
        redis) do_config_redis ;;
        *) die "用法: db config mysql|postgres|redis" ;;
      esac
      ;;
    connect-test|ping) do_connect_test "${2:-all}" ;;
    -h|--help) usage ;;
    --version) printf "%s\n" "$SCRIPT_VERSION" ;;
    *) die "未知操作：$1" ;;
  esac
}

interactive_loop() {
  local answer=""
  while true; do
    printf "\n数据库:\n"
    printf "  1. 服务状态\n  2. MySQL 配置\n  3. PostgreSQL 配置\n  4. Redis 配置\n  5. 连接探测\n  b. 返回\n"
    print_menu_nav_hint
    read_prompt "输入编号: " answer || return 1
    case "$answer" in
      1) do_status ;;
      2) do_config_mysql ;;
      3) do_config_postgres ;;
      4) do_config_redis ;;
      5) do_connect_test all ;;
      b|B|back|返回) return 0 ;;
      *) log_warn "无效输入" ;;
    esac
  done
}

main() {
  print_banner
  (($# > 0)) && run_action "$@" || interactive_loop
}

main "$@"
