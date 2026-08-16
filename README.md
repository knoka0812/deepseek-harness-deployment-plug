# DeepSeek Harness Public Access Patch

本仓库提供一个源码补丁和一个 Cordis 覆盖层，用于在明确接受匿名远程管理风险的前提下，让声明为可信 authority 的远程浏览器使用完整的 DeepSeek Harness Web UI；本仓库不负责安装、认证、反向代理或进程管理。

> **匿名公网访问安全警告：任何能够访问可信公开 authority 的人，都可能读写设置，检查凭据是否已配置、来源和可写状态，设置或取消设置凭据，调用宿主特权能力，并通过 Harness 的正常工具获得文件访问或命令执行能力。接口不会返回已存储的凭据值。`trustedHosts` 不是身份认证。请优先使用 HTTPS、反向代理认证和来源 IP 限制。**

## 根因与控制

| 控制 | 根因 | 安全默认值 | 公共访问覆盖层 |
| --- | --- | --- | --- |
| `pinPrivilegedToLoopback` | 特权 RPC 在外层可信请求检查后仍有第二层回环限制 | `true`，特权 RPC 仅回环可用 | `false`，已声明可信 authority 可访问 |
| `exposeAllSettingsNamespaces` | API 代理只暴露内置 allowlist 中的设置命名空间 | `false`，继续执行 allowlist | `true`，暴露所有已注册命名空间 |
| `allowRemoteSettingsPersistence` | 非回环浏览器固定使用内存设置模式 | `false`，远程页面不持久化到 Host | `true`，远程页面使用 Host 设置模式 |

三个选项都保持上游安全默认值；只有应用本仓库覆盖层时才显式开启匿名远程管理行为。

## 支持版本

仅支持 DeepSeek Harness commit `47f943859bef60e4160492346772ded9b24f765a`。

批准补丁的 SHA256 是 `014e8caddf3219da54bd04aae1c750630c2a9ae600ea6b03b7d72a8c48e8ac4e`，stable patch ID 是 `ad3debde77fd08aaf9520e9b620b0d9128d8aeba`。

## 目录

| 路径 | 内容 |
| --- | --- |
| `patches/public-access.patch` | 三项上游源码改动及聚焦测试 |
| `config/cordis.public-access.yml` | 监听全部接口并启用三项公共访问控制的覆盖层 |
| `scripts/verify.sh` | 只读检查补丁适用状态与配置完整性 |
| `docs/architecture.md` | 请求和设置数据流 |
| `docs/security.md` | 威胁模型与部署缓解措施 |
| `docs/troubleshooting.md` | 按症状定位故障层 |
| `docs/version-compatibility.md` | 支持版本与补丁刷新流程 |
| `docs/validation.md` | 支持 commit 上的最终验证证据与复现方法 |
| `docs/superpowers/specs/` | 保留的设计文档 |
| `docs/superpowers/plans/` | 保留的实施计划 |
| `LICENSE` | Apache License 2.0 |
| [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) | 上游派生补丁内容的 MIT 许可声明 |
| `SHA256SUMS` | 除自身外全部交付文件的 SHA256 内容清单 |

## 手动应用

```bash
git clone https://github.com/deepseek-ai/deepseek-harness.git /data/deepseek-harness
git -C /data/deepseek-harness checkout 47f943859bef60e4160492346772ded9b24f765a
git -C /data/deepseek-harness apply --check /path/to/public-access-kit/patches/public-access.patch
git -C /data/deepseek-harness apply /path/to/public-access-kit/patches/public-access.patch
pnpm --dir /data/deepseek-harness install --frozen-lockfile
pnpm --dir /data/deepseek-harness run build
```

`git apply --check` 失败时不要强行应用，先查看[版本兼容性](docs/version-compatibility.md)。

## 运行

```bash
dsh web \
  --patch /path/to/public-access-kit/config/cordis.public-access.yml \
  --trusted-host PUBLIC_AUTHORITY \
  --port 7860
```

`PUBLIC_AUTHORITY` 必须是浏览器地址栏可见的裸 authority，例如 `HOSTNAME` 或 `HOSTNAME:7860`，不能带协议、路径或末尾斜杠。

## 只读验证

```bash
/path/to/public-access-kit/scripts/verify.sh /data/deepseek-harness
```

脚本只读取补丁、覆盖层和目标 Git checkout，不会应用或反向应用补丁，也不会改写任何文件。它要求目标 HEAD 精确等于支持 commit；其他 commit 会退出 `1`，不能把补丁碰巧可应用视为通过验证，必须先移植、测试并重新生成补丁。脚本还验证补丁 SHA256、精确 12 文件 manifest、源文件 diff section 和覆盖层精确值，然后报告 `applicable` 或 `already-applied` 并打印五个聚焦测试文件与构建命令。

验证补丁包全部交付文件的内容：

```bash
sha256sum -c SHA256SUMS
```

`SHA256SUMS` 覆盖除其自身和 `.git` 元数据外的全部最终文件。任何未来内容修改后都必须重新生成该清单。完整的 Linux 验证证据、版本、计数和 warning 处理策略见 [`docs/validation.md`](docs/validation.md)。

## 运行时检查

```bash
PUBLIC_URL='https://PUBLIC_AUTHORITY'
WRONG_ORIGIN='https://wrong-origin.invalid'

# 首页应返回 200。
curl -sS -o /dev/null -w '%{http_code}\n' "$PUBLIC_URL/"

# 正确 Origin 调用 settings.describe 应返回 200。
curl -sS -o /dev/null -w '%{http_code}\n' -X POST \
  -H 'Content-Type: application/json' \
  -H "Origin: $PUBLIC_URL" \
  -H 'Sec-Fetch-Site: same-origin' \
  --data '{"type":"client-request","rpcId":"smoke","method":"settings.describe","payload":{}}' \
  "$PUBLIC_URL/api/settings.describe"

# 错误 Origin 必须继续返回 403。
curl -sS -o /dev/null -w '%{http_code}\n' -X POST \
  -H 'Content-Type: application/json' \
  -H "Origin: $WRONG_ORIGIN" \
  -H 'Sec-Fetch-Site: cross-site' \
  --data '{"type":"client-request","rpcId":"smoke","method":"settings.describe","payload":{}}' \
  "$PUBLIC_URL/api/settings.describe"
```

已由 Host 插件注册的第三方设置命名空间会自动暴露，不需要在本仓库逐个列名；但本补丁不能凭空创建未注册的 Host 命名空间，也不会绕过命名空间 schema 或插件 validator。

### 检查第三方命名空间

将 `PLUGIN_NS` 设置为一个已由 Host 插件注册的第三方命名空间。下面的命令调用 `settings.describe`，并在响应中找不到该命名空间时以非零状态退出：

```bash
: "${PLUGIN_NS:?export PLUGIN_NS as a registered third-party namespace}"
export PUBLIC_URL PLUGIN_NS

SETTINGS_DESCRIBE=$(curl --fail-with-body -sS -X POST \
  -H 'Content-Type: application/json' \
  -H "Origin: $PUBLIC_URL" \
  -H 'Sec-Fetch-Site: same-origin' \
  --data '{"type":"client-request","rpcId":"namespace-check","method":"settings.describe","payload":{}}' \
  "$PUBLIC_URL/api/settings.describe")
export SETTINGS_DESCRIBE

node <<'NODE'
const response = JSON.parse(process.env.SETTINGS_DESCRIBE)
if (response.result?.ok !== true) {
  throw new Error(`settings.describe failed: ${JSON.stringify(response.result)}`)
}
const namespaces = response.result.value.namespaces ?? []
if (!namespaces.some(view => view.ns === process.env.PLUGIN_NS)) {
  throw new Error(`registered namespace not exposed: ${process.env.PLUGIN_NS}`)
}
console.log(`namespace exposed: ${process.env.PLUGIN_NS}`)
NODE
```

### 保存并回读第三方设置

`PATCH_JSON` 必须是所选命名空间 schema 接受的 JSON object。例如可先按目标插件文档执行 `export PATCH_JSON='{"theme":"dark"}'`；这只是通用 JSON object 示例，不表示每个插件都有 `theme` 字段，必须改成该插件真实、schema-valid 的字段和值。

```bash
: "${PATCH_JSON:?export PATCH_JSON as a schema-valid JSON object}"
export PUBLIC_URL PLUGIN_NS PATCH_JSON

UPDATE_REQUEST=$(node -e '
const patch = JSON.parse(process.env.PATCH_JSON)
process.stdout.write(JSON.stringify({
  type: "client-request",
  rpcId: "third-party-update",
  method: "settings.update",
  payload: { ns: process.env.PLUGIN_NS, patch },
}))')

UPDATE_RESPONSE=$(curl --fail-with-body -sS -X POST \
  -H 'Content-Type: application/json' \
  -H "Origin: $PUBLIC_URL" \
  -H 'Sec-Fetch-Site: same-origin' \
  --data "$UPDATE_REQUEST" \
  "$PUBLIC_URL/api/settings.update")
export UPDATE_RESPONSE

node -e '
const response = JSON.parse(process.env.UPDATE_RESPONSE)
if (response.result?.ok !== true) throw new Error(`settings.update failed: ${JSON.stringify(response.result)}`)
console.log(`setting saved: ${process.env.PLUGIN_NS}`)'

READBACK_RESPONSE=$(curl --fail-with-body -sS -X POST \
  -H 'Content-Type: application/json' \
  -H "Origin: $PUBLIC_URL" \
  -H 'Sec-Fetch-Site: same-origin' \
  --data '{"type":"client-request","rpcId":"third-party-readback","method":"settings.describe","payload":{}}' \
  "$PUBLIC_URL/api/settings.describe")
export READBACK_RESPONSE

node <<'NODE'
const response = JSON.parse(process.env.READBACK_RESPONSE)
if (response.result?.ok !== true) {
  throw new Error(`settings.describe readback failed: ${JSON.stringify(response.result)}`)
}
const view = (response.result.value.namespaces ?? [])
  .find(item => item.ns === process.env.PLUGIN_NS)
if (!view) throw new Error(`namespace missing on readback: ${process.env.PLUGIN_NS}`)
const patch = JSON.parse(process.env.PATCH_JSON)

function deepEqual(actual, expected) {
  if (Object.is(actual, expected)) return true
  if (Array.isArray(actual) || Array.isArray(expected)) {
    return Array.isArray(actual) && Array.isArray(expected)
      && actual.length === expected.length
      && actual.every((item, index) => deepEqual(item, expected[index]))
  }
  if (actual === null || expected === null
    || typeof actual !== 'object' || typeof expected !== 'object') return false
  const actualKeys = Object.keys(actual).sort()
  const expectedKeys = Object.keys(expected).sort()
  return actualKeys.length === expectedKeys.length
    && actualKeys.every((key, index) => key === expectedKeys[index]
      && deepEqual(actual[key], expected[key]))
}

for (const [key, expected] of Object.entries(patch)) {
  if (!deepEqual(view.value?.[key], expected)) {
    throw new Error(`readback mismatch for ${process.env.PLUGIN_NS}.${key}`)
  }
}
console.log(`setting read back: ${process.env.PLUGIN_NS}`)
NODE
```

### 检查 WebSocket

以下命令使用 Node.js 22 内置 `WebSocket`，把 `PUBLIC_URL` 的 `http:`/`https:` 自动转换为 `ws:`/`wss:`。任一路径在 10 秒内未连接或发生错误，进程都会以非零状态退出：

```bash
export PUBLIC_URL

node --input-type=module <<'NODE'
const base = new URL(process.env.PUBLIC_URL)
base.protocol = base.protocol === 'https:' ? 'wss:' : 'ws:'

function connect(path) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, base)
    const socket = new WebSocket(url)
    const timer = setTimeout(() => {
      socket.close()
      reject(new Error(`WebSocket timeout: ${url}`))
    }, 10_000)
    socket.addEventListener('open', () => {
      clearTimeout(timer)
      console.log(`WebSocket connected: ${url}`)
      socket.close()
      resolve()
    }, { once: true })
    socket.addEventListener('error', () => {
      clearTimeout(timer)
      reject(new Error(`WebSocket failed: ${url}`))
    }, { once: true })
  })
}

await connect('/api/events.mux')
await connect('/api/events.host')
NODE
```

## 进一步阅读

- [架构](docs/architecture.md)
- [安全](docs/security.md)
- [故障排查](docs/troubleshooting.md)
- [版本兼容性](docs/version-compatibility.md)
- [验证证据](docs/validation.md)
