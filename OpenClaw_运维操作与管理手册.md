# OpenClaw 运维操作与管理手册（Ubuntu，安装后）

版本：v1.0  
适用对象：Ops / SRE / 平台运维  
适用场景：已完成 OpenClaw 安装后的日常运行维护、故障处理与升级管理

## 1. 目标与范围

本手册用于规范 OpenClaw 在 Ubuntu 环境下的运维工作，覆盖：
- 服务启停与状态检查
- 健康检查与日志排障
- 配置与密钥管理
- 升级与回滚预案
- 备份与恢复

## 2. 环境基线

- 操作系统：Ubuntu
- 安装方式：用户目录安装（例如 `~/.openclaw`）
- 主要命令：`openclaw`、`claude`
- 默认 Gateway 端口：`18789`

建议先确认版本与路径：

```bash
which openclaw
openclaw --version
claude --version
```

## 3. 安装后交付验收（必须执行）

按顺序执行以下命令：

```bash
openclaw doctor
openclaw gateway status
openclaw status
openclaw health
openclaw dashboard
```

验收通过标准：
- `doctor` 无阻断错误
- `gateway status` 显示 Runtime 为 running，RPC probe 为 ok
- `health` 能正常返回状态
- `dashboard` 可打开控制台页面

## 4. 运行模式与服务托管

### 4.1 前台运行（临时调试）

```bash
openclaw gateway --port 18789
openclaw gateway --port 18789 --verbose
```

### 4.2 受控服务运行（生产推荐）

```bash
openclaw gateway install
openclaw gateway status
openclaw gateway restart
openclaw gateway stop
```

Linux 用户级 systemd 服务常见补充操作：

```bash
systemctl --user enable --now openclaw-gateway.service
sudo loginctl enable-linger <your-user>
```

说明：
- 如果使用 profile，服务名可能为 `openclaw-gateway-<profile>.service`
- 为保证用户退出后服务仍常驻，需启用 `linger`

## 5. 日常运维 SOP

### 5.1 状态巡检

```bash
openclaw gateway status
openclaw status
openclaw channels status --probe
openclaw health --verbose
```

### 5.2 启停与重启

```bash
openclaw gateway start
openclaw gateway stop
openclaw gateway restart
```

### 5.3 日志查看

```bash
openclaw logs
openclaw logs --follow
openclaw logs --follow --local-time
openclaw logs --json
```

### 5.4 远程连通性与探测

```bash
openclaw gateway probe
openclaw gateway status --deep
```

需要经 SSH 隧道访问时：

```bash
ssh -N -L 18789:127.0.0.1:18789 user@host
```

## 6. 配置与密钥管理

### 6.1 配置调整建议流程

1. 先执行 `openclaw config get <key>` 查看当前配置
2. 通过 `openclaw configure` 或 `openclaw config set` 修改
3. 修改后执行 `openclaw doctor`
4. 必要时执行 `openclaw gateway restart`

### 6.2 密钥安全运维（推荐标准流程）

```bash
openclaw secrets audit --check
openclaw secrets configure
openclaw secrets apply --from /tmp/openclaw-secrets-plan.json --dry-run
openclaw secrets apply --from /tmp/openclaw-secrets-plan.json
openclaw secrets reload
openclaw secrets audit --check
```

注意：
- `secrets reload` 失败时会保留 last-known-good 运行快照
- 严禁在工单、脚本和聊天记录中明文传递凭据

## 7. 升级管理（变更窗口执行）

### 7.1 升级前检查

```bash
openclaw update status
openclaw gateway status
openclaw doctor
```

备份以下关键目录：
- `~/.openclaw/openclaw.json`
- `~/.openclaw/credentials/`
- `~/.openclaw/workspace`

### 7.2 执行升级

方式 A（CLI 统一升级）：

```bash
openclaw update
```

方式 B（安装器升级）：

```bash
curl -fsSL https://openclaw.ai/install.sh | bash
```

### 7.3 升级后验证

```bash
openclaw doctor
openclaw gateway restart
openclaw health
openclaw status
```

如需切换渠道：

```bash
openclaw update --channel stable
openclaw update --channel beta
openclaw update --channel dev
```

## 8. 故障排查 Runbook（2 分钟快速诊断）

按顺序执行：

```bash
openclaw status
openclaw status --all
openclaw gateway probe
openclaw gateway status
openclaw doctor
openclaw channels status --probe
openclaw logs --follow
```

常见故障签名与处理：
- `Gateway start blocked: set gateway.mode=local`
  - 处理：设置 `gateway.mode=local` 或重新执行 `openclaw configure`
- `refusing to bind gateway ... without auth`
  - 处理：非 loopback 绑定必须配置 token/password
- `another gateway instance is already listening` / `EADDRINUSE`
  - 处理：端口冲突，释放端口或改用新端口
- `unauthorized`
  - 处理：检查 URL 与 token/password 是否匹配

## 9. 备份与恢复

### 9.1 备份策略

- 每日：配置与凭据（`openclaw.json`、`credentials/`）
- 每周：`workspace` 与关键日志归档
- 每次变更前：全量快照

### 9.2 恢复流程

1. 停止 Gateway：`openclaw gateway stop`
2. 恢复配置/凭据/工作目录文件
3. 运行修复检查：`openclaw doctor`
4. 启动服务：`openclaw gateway start`
5. 验证：`openclaw gateway status && openclaw health`

## 10. 值班巡检清单

每日：
- `openclaw gateway status`
- `openclaw health`
- `openclaw channels status --probe`
- 查看最近日志是否有重复错误

每周：
- `openclaw doctor --deep`
- `openclaw secrets audit --check`
- `openclaw update status`
- 备份校验抽样恢复

## 11. 附录：常用命令速查

```bash
# 服务
openclaw gateway install
openclaw gateway status
openclaw gateway start
openclaw gateway stop
openclaw gateway restart

# 巡检
openclaw status
openclaw health
openclaw doctor
openclaw channels status --probe

# 日志
openclaw logs --follow --local-time

# 升级
openclaw update
openclaw update status

# 安全与密钥
openclaw secrets audit --check
openclaw secrets reload
```

## 12. 官方参考文档

- CLI 命令参考：https://docs.openclaw.ai/cli/reference
- Gateway 与 Ops Runbook：https://docs.openclaw.ai/gateway/gateway-and-ops
- 升级流程：https://docs.openclaw.ai/getting-started/update-openclaw
- 安装说明：https://docs.openclaw.ai/cli/installation
- Claude Code 安装：https://docs.anthropic.com/en/docs/claude-code/setup
