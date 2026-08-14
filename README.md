# DeepSeek Harness 公网部署插件

把 DeepSeek Harness Web UI 以**完全公开、无登录认证**的方式监听 `0.0.0.0`，并放开「设置 / Agent 预设 / 凭据 / 宿主目录」等特权接口的回环限制。

> **安全警告**：本插件让任何能访问公网地址的人都能读写设置、管理凭据、打开宿主目录/文件，并可能获得命令执行能力。`trustedHosts` 只是 DNS-rebinding / 跨站防护，**不是认证**。仅在明确接受匿名公网访问时使用。正式环境请配合来源 IP 限制、反向代理认证和非特权用户。

## 文件说明

| 文件 | 作用 |
| --- | --- |
| `cordis.yml` | `dsh web --patch` 覆盖层：监听 `0.0.0.0:7860`，`pinPrivilegedToLoopback: false` |
| `cordis.example.yml` | 示例：监听 `0.0.0.0:7086`（配合端口映射场景） |
| `pinPrivilegedToLoopback.patch` | 给 `client-connection` 加配置开关的源码补丁（一次性，默认仍安全） |
| `dsh-start.sh` | 启动脚本示例（nohup 后台运行 + 就绪探测） |

## 为什么需要一个源码补丁

特权接口（`settings.*`、`credentials.*`、`agentPreset.read/copy/openDocument/remove`、`host.pickDirectory/openPath`、`llm.discoverModels`）的二次回环限制原本硬编码在 `packages/client/connection/src/index.ts` 里，没有配置项。本仓库的 `pinPrivilegedToLoopback.patch` 给该插件新增 `pinPrivilegedToLoopback` 开关：

- 默认 `true`：保持上游安全行为（特权方法仍回环锁定）。
- 设 `false`：声明的 `trustedHosts` authority 也能访问这些方法，外层 Host/Origin/Sec-Fetch-Site 信任栅栏**仍然保留**，未声明的 Host 仍返回 403。

`0.0.0.0` 监听本身**不需要改源码**：`webserver` 插件的 schema 本来就接受 `0.0.0.0`，补丁层直接覆盖 `webserver.host` 即可（不必传 `--host 0.0.0.0`，也不用改 `startup.ts`）。

## 部署步骤

### 1. 克隆源码并应用补丁

```bash
git clone --depth 1 https://github.com/deepseek-ai/deepseek-harness.git /data/deepseek-harness
cd /data/deepseek-harness
git apply /path/to/pinPrivilegedToLoopback.patch
```

### 2. 安装 Node.js 与 pnpm

```bash
# 用独立 conda 环境，避免污染系统 Node
/data/miniconda/bin/conda create -y -p /data/miniconda/envs/deepseek-harness \
  --override-channels -c conda-forge 'nodejs>=24,<25'

export PATH=/data/miniconda/envs/deepseek-harness/bin:$PATH
corepack enable
corepack prepare pnpm@11.7.0 --activate
```

### 3. 安装依赖并构建

```bash
export PATH=/data/miniconda/envs/deepseek-harness/bin:$PATH
pnpm --dir /data/deepseek-harness install --frozen-lockfile
pnpm --dir /data/deepseek-harness run build
```

### 4.（可选）构建 Landlock 沙箱 runner

```bash
sudo apt-get update
sudo apt-get install -y --no-install-recommends musl-tools
pnpm --dir /data/deepseek-harness/native/landlock-run run build:native
```

### 5. 准备覆盖层与启动脚本

把 `cordis.yml`（或按端口映射改好的 `cordis.example.yml`）放到 `/data/deepseek-harness-runtime/cordis.yml`，把 `dsh-start.sh` 里的 `PUBLIC_AUTHORITY` 改成浏览器地址栏里的 `IP/域名[:端口]`。

### 6. 启动

```bash
dsh web \
  --patch /data/deepseek-harness-runtime/cordis.yml \
  --trusted-host PUBLIC_AUTHORITY \
  --port 7860
```

`--trusted-host` 只填裸 authority（不带 `http://`、路径或斜杠），可重复多个：

```bash
dsh web --patch ./cordis.yml --trusted-host harness.example.com 203.0.113.10:7860
```

## 验证

```bash
PUBLIC_URL='https://harness.example.com:30499'

# 首页
curl -sS -o /dev/null -w '%{http_code}\n' "$PUBLIC_URL/"   # 200

# 特权接口（正确 Origin）
curl -sS -o /dev/null -w '%{http_code}\n' -X POST \
  -H 'Content-Type: application/json' \
  -H "Origin: $PUBLIC_URL" -H 'Sec-Fetch-Site: same-origin' \
  --data '{"type":"client-request","rpcId":"check","method":"settings.describe","payload":{}}' \
  "$PUBLIC_URL/api/settings.describe"   # 200（不再是 403）

# 错误 Origin 仍应 403（确认信任栅栏没被整体删除）
curl -sS -o /dev/null -w '%{http_code}\n' -X POST \
  -H 'Content-Type: application/json' \
  -H 'Origin: https://evil.example' -H 'Sec-Fetch-Site: same-origin' \
  --data '{"type":"client-request","rpcId":"check","method":"host.describe","payload":{}}' \
  "$PUBLIC_URL/api/host.describe"   # 403
```

WebSocket 路径（`/api/events.mux`、`/api/events.host`）走同一信任栅栏；反向代理或端口映射必须支持 WebSocket Upgrade。
