# DeepSeek Harness 公网部署补丁

把 DeepSeek Harness Web UI 以**完全公开、无登录认证**的方式监听 `0.0.0.0`，并放开远程浏览器使用特权接口、第三方插件设置和 Host 设置持久化时遇到的限制。

> **安全警告**：本补丁会把 DeepSeek Harness 变成匿名远程管理入口。任何能够访问公网地址的人，都可能读写设置、检查或修改凭据状态、打开宿主目录/文件，并通过 Harness 的正常工具获得文件访问或命令执行能力。`trustedHosts` 只是 Host/Origin 和 DNS-rebinding 防护，**不是登录认证**。正式环境请增加反向代理认证、来源 IP 限制，并使用非 root 用户运行。

## 文件说明

| 文件 | 作用 |
| --- | --- |
| `patches/public-access.patch` | 一次性源码补丁，增加三个默认安全的公网访问开关及对应测试 |
| `config/cordis.public-access.yml` | `dsh web --patch` 覆盖层：监听 `0.0.0.0` 并启用三个公网开关 |
| `scripts/verify.sh` | 只读检查目标版本、补丁完整性和适用状态 |
| `docs/architecture.md` | 三层限制和请求流程说明 |
| `docs/security.md` | 风险与安全加固建议 |
| `docs/troubleshooting.md` | 常见故障排查 |
| `docs/version-compatibility.md` | 支持版本和补丁升级方法 |
| `docs/validation.md` | 测试和构建验证记录 |
| `SHA256SUMS` | 仓库交付文件校验和 |
| `LICENSE` / `THIRD_PARTY_NOTICES.md` | 本仓库及上游派生内容的许可说明 |

## 为什么需要源码补丁

DeepSeek Harness 公网访问有三层相互独立的限制，只处理其中一层会出现“页面能打开，但设置仍不可用”的情况。

### 1. 特权接口仍被限制为回环访问

`settings.*`、`credentials.*`、`agentPreset.read/copy/openDocument/remove`、`host.pickDirectory/openPath`、`llm.discoverModels` 等接口在通过 `trustedHosts` 后，还会执行第二次回环校验。

补丁增加：

```text
pinPrivilegedToLoopback
```

- 默认 `true`：保持上游行为，特权接口仍只允许回环访问。
- 设为 `false`：已声明的 `trustedHosts` authority 可以访问特权接口，外层 Host/Origin/Sec-Fetch-Site 检查仍然保留。

### 2. 第三方设置命名空间不在白名单

Host API Proxy 默认只向设置页暴露内置白名单里的 namespace。即使 `pet`、`describe-image` 等插件已经注册设置 schema，远程设置页仍可能提示“未暴露本插件的配置命名空间”。

补丁增加：

```text
exposeAllSettingsNamespaces
```

- 默认 `false`：继续执行上游设置 namespace 白名单。
- 设为 `true`：暴露所有已经由 Host 插件注册的设置 namespace。

它不会凭空创建 namespace，也不会绕过插件 schema、validator 或设置存储校验。

### 3. 远程浏览器强制使用内存设置模式

非 `localhost` 页面默认把设置作用域切到 `memory` 模式，因此即使 Host 已暴露 namespace，插件表单仍可能显示不可用或无法持久化。

补丁增加：

```text
allowRemoteSettingsPersistence
```

- 默认 `false`（上游行为）：远程页面继续使用内存设置模式。
- 设为 `true`：远程页面通过 Host API 读取、刷新和保存设置。

由于 DSH 的 boot manifest 目前不会把 Cordis 覆盖层配置带到浏览器端，`ui-settings` 客户端插件接收不到覆盖层里的 `allowRemoteSettingsPersistence: true`。因此本补丁同时把客户端 `SettingsScopeBinder` 的默认值改为 `true`，确保公网部署下远程页面直接走 Host 设置持久化。

前两个开关默认保持上游安全行为；第三个开关在客户端被本补丁显式默认开启，以解决 boot manifest 不透传配置的问题。

## Shell 沙箱说明

Shell 提示“沙箱后端不可用”或拒绝运行 `bash`，不属于本公网访问补丁处理的三层限制。Harness 在 Linux 上优先使用可工作的 Bubblewrap（`bwrap`），探测失败后回退到 Landlock；两者都不可用时会失败闭合，拒绝无沙箱执行命令。

普通 Linux 服务器建议优先安装并验证 `bwrap`。容器环境可能因 user/mount namespace、AppArmor 或 capability 限制导致 `bwrap` 已安装但仍返回 `Operation not permitted`，这种情况下可使用 Harness 官方 Landlock 后端。源码 checkout 还可能需要先构建未纳入 Git 的平台 launcher。完整命令和判断方法见[故障排查：Shell 沙箱后端不可用](docs/troubleshooting.md#shell-沙箱后端不可用)。

## 支持版本

当前补丁只支持 DeepSeek Harness commit：

```text
47f943859bef60e4160492346772ded9b24f765a
```

不要在其他版本上跳过 `git apply --check` 强行应用。上游源码变化后，请参考 [`docs/version-compatibility.md`](docs/version-compatibility.md) 重新移植和生成补丁。

## 部署步骤

### 1. 克隆源码并切换到支持版本

```bash
git clone https://github.com/deepseek-ai/deepseek-harness.git /data/deepseek-harness
git -C /data/deepseek-harness checkout 47f943859bef60e4160492346772ded9b24f765a
```

### 2. 检查并应用补丁

假设本仓库位于 `/data/deepseek-harness-deployment-plug`：

```bash
git -C /data/deepseek-harness apply --check \
  /data/deepseek-harness-deployment-plug/patches/public-access.patch

git -C /data/deepseek-harness apply \
  /data/deepseek-harness-deployment-plug/patches/public-access.patch
```

也可以使用只读验证脚本：

```bash
/data/deepseek-harness-deployment-plug/scripts/verify.sh \
  /data/deepseek-harness
```

预期输出之一：

```text
patch state: applicable
```

或已经应用时：

```text
patch state: already-applied
```

### 3. 安装 Node.js 与 pnpm

DeepSeek Harness 要求 Node.js `^22.19.0 || >=24.0.0`，并指定 pnpm `11.7.0`。

下面使用独立 Conda 环境，避免污染系统 Node：

```bash
/data/miniconda/bin/conda create -y \
  -p /data/miniconda/envs/deepseek-harness \
  --override-channels \
  -c conda-forge \
  'nodejs>=24,<25'

export PATH=/data/miniconda/envs/deepseek-harness/bin:$PATH
corepack enable
corepack prepare pnpm@11.7.0 --activate
```

确认版本：

```bash
node --version
pnpm --version
```

### 4. 安装依赖并构建

```bash
export PATH=/data/miniconda/envs/deepseek-harness/bin:$PATH
pnpm --dir /data/deepseek-harness install --frozen-lockfile
pnpm --dir /data/deepseek-harness run build
```

### 5. 启动服务

```bash
export PATH=/data/miniconda/envs/deepseek-harness/bin:$PATH

node /data/deepseek-harness/apps/cli/lib/bin.js web \
  --patch /data/deepseek-harness-deployment-plug/config/cordis.public-access.yml \
  --trusted-host PUBLIC_AUTHORITY \
  --port 7860
```

`PUBLIC_AUTHORITY` 必须填写浏览器地址栏实际使用的裸 authority，不要带协议、路径或末尾斜杠。

常见写法：

| 浏览器地址 | `--trusted-host` |
| --- | --- |
| `http://203.0.113.10:7860/` | `203.0.113.10:7860` |
| `https://harness.example.com/` | `harness.example.com` |
| `https://harness.example.com:8443/` | `harness.example.com:8443` |

可以同时声明多个入口：

```bash
node /data/deepseek-harness/apps/cli/lib/bin.js web \
  --patch /data/deepseek-harness-deployment-plug/config/cordis.public-access.yml \
  --trusted-host harness.example.com 203.0.113.10:7860 \
  --port 7860
```

## 覆盖层内容

`config/cordis.public-access.yml` 会启用：

```yaml
- id: webserver
  config:
    host: '0.0.0.0'
    port: !!js ctx.webStartup.port ?? 7860

- id: connection
  config:
    trustedHosts: !!js ctx.webRuntime.trustedHosts
    pinPrivilegedToLoopback: false

- id: api-gateway
  config:
    exposeAllSettingsNamespaces: true

- id: ui-settings
  config:
    allowRemoteSettingsPersistence: true
```

## 验证

先设置浏览器实际访问地址：

```bash
PUBLIC_URL='https://harness.example.com'
```

### 1. 首页

```bash
curl -sS -o /dev/null -w '%{http_code}\n' "$PUBLIC_URL/"
```

预期：

```text
200
```

### 2. 特权接口

```bash
curl -sS -o /dev/null -w '%{http_code}\n' -X POST \
  -H 'Content-Type: application/json' \
  -H "Origin: $PUBLIC_URL" \
  -H 'Sec-Fetch-Site: same-origin' \
  --data '{"type":"client-request","rpcId":"settings-check","method":"settings.describe","payload":{}}' \
  "$PUBLIC_URL/api/settings.describe"
```

预期：

```text
200
```

### 3. 错误 Origin 仍被拒绝

```bash
curl -sS -o /dev/null -w '%{http_code}\n' -X POST \
  -H 'Content-Type: application/json' \
  -H 'Origin: https://wrong-origin.invalid' \
  -H 'Sec-Fetch-Site: cross-site' \
  --data '{"type":"client-request","rpcId":"origin-check","method":"host.describe","payload":{}}' \
  "$PUBLIC_URL/api/host.describe"
```

预期：

```text
403
```

### 4. 第三方插件设置

进入设置页后，已由 Host 插件注册的第三方 namespace 应自动显示可编辑表单，例如图像理解、宠物、任务看板等插件。

如果仍提示“未暴露本插件的配置命名空间”，请先执行浏览器强制刷新：

```text
Ctrl + Shift + R
```

然后参考 [`docs/troubleshooting.md`](docs/troubleshooting.md) 检查：

- 是否运行了重新构建后的 Host 和 Web bundle。
- `settings.describe` 是否包含目标 namespace。
- 目标插件是否真的在 Host 侧注册了设置 schema。

### 5. WebSocket

页面依赖以下 WebSocket 路径：

```text
/api/events.mux
/api/events.host
```

反向代理或端口映射必须支持 WebSocket Upgrade，并保留正确的 Host 和 Origin。

## 校验补丁包

仓库根目录执行：

```bash
sha256sum -c SHA256SUMS
```

补丁身份：

```text
SHA256: 00c49c14460c581a8695f3053fe39c3693b6fc754f6edcb1e627fddb1ec225ef
stable patch ID: 4698e67e76e2cbdee4cd4e5bd55c2db5c8cbb491
```

## 进一步阅读

- [架构说明](docs/architecture.md)
- [安全说明](docs/security.md)
- [故障排查](docs/troubleshooting.md)
- [版本兼容性](docs/version-compatibility.md)
- [验证记录](docs/validation.md)

## 许可证

本仓库原创内容使用 Apache License 2.0。`patches/public-access.patch` 包含基于 DeepSeek Harness MIT 许可源码生成的上下文和修改，详见 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。
