# netool 功能路线图

> **v1.0 已实现** `tools/apps/` 下全部 Phase 1 只读模块。下文保留设计说明供后续 Phase 2（可写操作）参考。

---

## 1. 总体架构

```
main.sh
  └── tools/apps/          # 新分类：应用与中间件
        ├── web.sh         # Web 服务器（Nginx / Apache / Caddy）
        ├── db.sh          # 数据库（MySQL / PostgreSQL / Redis）
        ├── app-config.sh  # 通用应用配置扫描
        ├── audit.sh       # 用户 / 权限 / 文件权限审计
        ├── logs.sh        # 日志与监控配置查看 / 清理建议
        └── cron-templates.sh  # 常用定时任务模板
```

每个子模块遵循现有约定：

- `source load_common.sh` + 二级交互菜单
- CLI：`./main.sh web check nginx` / `./main.sh db status mysql`
- 远程 curl 模式同样可用

---

## 2. Web 服务器配置检查（`web.sh`）

### 目标

检测 Nginx / Apache / Caddy 是否安装，解析主配置与站点配置，输出**风险摘要**（不自动改文件）。

### 子命令

| 命令 | 说明 |
|------|------|
| `status` | 服务状态、监听端口、配置路径 |
| `check nginx` | `nginx -t`、include 树、SSL 证书路径、server_name |
| `check apache` | `apachectl configtest`、VirtualHost、mod 列表 |
| `check caddy` | Caddyfile 路径、反代 upstream、自动 HTTPS |
| `list-sites` | 列出 enabled 站点与 root 目录 |
| `security-scan` | 隐藏版本号、HTTP→HTTPS、弱 cipher 提示（只读） |

### 实现要点

- 配置解析优先调用官方工具（`nginx -T` / `apache2ctl -S`）
- 无 root 时降级为只读路径检测 + 提示 sudo
- 输出统一表格：文件 · 行号 · 问题 · 建议

---

## 3. 数据库配置（`db.sh`）

### 目标

查看常见数据库**安装状态、监听地址、数据目录、配置路径**；可选连接测试（用户手动提供 socket/端口，**不内置默认密码**）。

### 子命令

| 命令 | 说明 |
|------|------|
| `status` | 探测 mysql/mariadb、postgresql、redis 是否运行 |
| `config mysql` | 展示 `my.cnf` 片段：bind-address、datadir、log_bin |
| `config postgres` | `postgresql.conf` / `pg_hba.conf` 路径与关键项 |
| `config redis` | bind、requirepass 是否设置（仅提示是否为空，不打印密码） |
| `connect-test` | 使用 `mysqladmin ping` / `pg_isready` / `redis-cli ping` |

### 安全

- 禁止读取或回显 `.my.cnf` 密码
- 改配置类操作 Phase 2 再做，Phase 1 只读

---

## 4. 应用配置文件扫描（`app-config.sh`）

### 目标

在常见路径搜索应用配置（Docker Compose、`.env`、PM2、Supervisor），生成**清单报告**。

### 扫描范围（可配置）

| 类型 | 典型路径 |
|------|----------|
| Docker Compose | `/opt/*/docker-compose.yml`, `~/apps/` |
| 环境变量 | `.env`（只列 key 名，不列 secret 值） |
| Supervisor | `/etc/supervisor/conf.d/` |
| Systemd 单元 | 自定义 app service |

### 子命令

- `scan [--path DIR]` — 生成报告
- `secrets-audit` — 标记 `.env` 权限过宽（如 644 root 可读）

---

## 5. 用户与权限审计（`audit.sh`）

与现有 `user.sh`（管理向）区分：**只读审计**。

| 命令 | 说明 |
|------|------|
| `users` | UID 0 账户、无密码锁定、长期未登录 |
| `sudoers` | `/etc/sudoers` 与 `/etc/sudoers.d/` 语法检查（visudo -c） |
| `ssh-keys` | authorized_keys 数量、重复 key、空口令登录是否禁用 |
| `permissions` | world-writable 敏感路径（`/etc/passwd` 以外自定义列表） |

---

## 6. 日志与监控（`logs.sh`）

| 命令 | 说明 |
|------|------|
| `usage` | journald / `/var/log` / docker 日志占用（复用 logclean 部分逻辑） |
| `tail-errors` | 最近 N 条 ERROR（nginx、app、syslog 可参数指定） |
| `monitor` | 检测 node_exporter / prometheus / zabbix agent 是否安装 |
| `rotate-hint` | logrotate 配置是否存在、建议命令（只读） |

与 `logclean.sh` 边界：`logclean` = 清理执行；`logs` = 查看 + 建议。

---

## 7. 常用自动化定时任务（`cron-templates.sh`）

### 目标

提供**模板化** crontab 片段，用户预览后选择性安装（不静默写入）。

### 模板示例

| ID | 说明 | 默认 schedule |
|----|------|----------------|
| `cert-renew` | certbot renew + nginx reload | 每月 1 日 3:00 |
| `disk-alert` | 根分区 >85% 发邮件/写日志 | 每小时 |
| `log-truncate` | 压缩 7 天前 nginx 日志 | 每天 2:00 |
| `backup-mysql` | mysqldump（需用户填路径） | 每天 4:00 |

### 流程

1. `./main.sh cron-templates list`
2. `./main.sh cron-templates show cert-renew`
3. `./main.sh cron-templates install cert-renew --plan` → 确认 → 写入 `/etc/cron.d/netool-*`

与现有 `cron.sh` 边界：`cron.sh` = 管理已有 crontab；`cron-templates` = 最佳实践模板库。

---

## 8. main.sh 菜单集成（建议编号）

在「应用与中间件」分区（主菜单 26–30 预留）：

| 编号 | 工具 |
|------|------|
| 26 | Web 配置检查 |
| 27 | 数据库配置 |
| 28 | 应用配置扫描 |
| 29 | 权限审计 |
| 30 | 日志/监控 |

（当前主菜单已占用 1–25；扩展时可改为二级「应用」入口 `apps` 再分子菜单，避免编号膨胀。）

---

## 9. 实施阶段

| 阶段 | 内容 | 优先级 |
|------|------|--------|
| **P0** | `web.sh status + check nginx` | 高 |
| **P1** | `db.sh status` + `audit.sh users/sudoers` | 高 |
| **P2** | `logs.sh usage` + `app-config.sh scan` | 中 |
| **P3** | `cron-templates` + Caddy/Apache 完整检查 | 中 |
| **P4** | 可选改配置（备份后写入） | 低 |

---

## 10. 测试与文档

- 每个新脚本：`bash -n` + Docker 多发行版 fixture（CI matrix 可选）
- README 增加「应用运维」章节
- `versions.env` 注册新组件版本

---

## 11. 依赖与约束

- 不引入 Python 运行时（保持纯 Bash 或调用系统命令）
- 可选增强：`jq` 解析 JSON 配置时检测命令是否存在并降级
- 与 lmirrors/mirror 无交叉；与 security/user 互补而非重复
