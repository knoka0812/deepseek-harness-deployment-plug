# 故障排查

先按症状确定故障层，不要通过删除可信请求检查来绕过问题。

| 症状 | 可能原因 |
| --- | --- |
| 公网页面超时 | 监听地址、防火墙、端口映射或反向代理问题 |
| 所有 API 调用都返回 403 | 浏览器可见 authority 未加入 `trustedHosts`，或代理转发的 Host/Origin 不一致 |
| 只有设置或凭据接口返回 403 | `pinPrivilegedToLoopback` 未关闭，或运行的仍是旧构建 |
| 插件提示 namespace not exposed | `exposeAllSettingsNamespaces` 未启用、Host 插件未注册命名空间，或 Host 仍是旧构建 |
| 插件卡片出现但一直 unavailable | `allowRemoteSettingsPersistence` 未启用，或浏览器缓存了旧客户端 bundle |
| 保存请求到达服务端但被拒绝 | 命名空间 schema 或插件 validator 拒绝该值 |
| 页面持续重连 | WebSocket upgrade、Host 转发或 Origin 转发错误 |
| Shell 提示沙箱后端不可用、`bash` 被拒绝 | Linux 上 `bwrap` 和 Landlock 都未通过功能探测；这是本地沙箱问题，不是公网补丁问题 |

## 基础状态

```bash
git -C /data/deepseek-harness rev-parse HEAD
git -C /data/deepseek-harness status --short
/path/to/public-access-kit/scripts/verify.sh /data/deepseek-harness
```

HEAD 必须精确等于支持 commit。若不同，验证脚本打印支持值和实际值并退出 `1`；不要在该 checkout 上继续应用，按版本兼容文档移植并重新生成补丁。支持 commit 上报告 `applicable` 表示补丁尚未应用，报告 `already-applied` 表示已应用；脚本本身不会修改 checkout。

若验证器报告 patch SHA、12 文件 manifest、源 diff section 或 overlay row/value 不匹配，应视为补丁包内容损坏或未经记录的修改。先运行 `sha256sum -c SHA256SUMS`，不要跳过检查继续部署。

## 监听与首页

```bash
PUBLIC_URL='https://PUBLIC_AUTHORITY'
curl -sS -D - -o /dev/null "$PUBLIC_URL/"
```

首页超时时，依次检查 Harness 是否监听预期端口、本机防火墙、端口映射、代理 upstream 与 HTTPS 终止配置。覆盖层中的服务端端口是 `7860`，除非 CLI `--port` 覆盖。

## Host 与 Origin

```bash
curl -sS -D - -o /dev/null -X POST \
  -H 'Content-Type: application/json' \
  -H "Origin: $PUBLIC_URL" \
  -H 'Sec-Fetch-Site: same-origin' \
  --data '{"type":"client-request","rpcId":"diag","method":"settings.describe","payload":{}}' \
  "$PUBLIC_URL/api/settings.describe"
```

若所有 API 都是 `403`，确认 `--trusted-host` 使用浏览器地址栏中的裸 authority，不带协议或路径；同时检查代理是否保留浏览器 Host 与 Origin。

## 检查设置命名空间

保存完整响应并查看 `settings.describe` 中的命名空间：

```bash
curl -sS -X POST \
  -H 'Content-Type: application/json' \
  -H "Origin: $PUBLIC_URL" \
  -H 'Sec-Fetch-Site: same-origin' \
  --data '{"type":"client-request","rpcId":"namespaces","method":"settings.describe","payload":{}}' \
  "$PUBLIC_URL/api/settings.describe" | jq '.result.value.namespaces[] | .ns'
```

若目标命名空间缺失，先确认 `config/cordis.public-access.yml` 中 `exposeAllSettingsNamespaces: true` 已实际加载，再检查对应 Host 插件是否启动并向 settings provider 注册了命名空间。补丁不能创建未注册命名空间。

## 旧客户端缓存

插件卡片存在但持续 `unavailable`，且服务端配置正确时，浏览器可能仍在使用旧 bundle。先在开发者工具中勾选禁用缓存并执行硬刷新，或清除该站点缓存后重新加载；同时确认部署目录中的客户端构建产物来自应用补丁后的 `pnpm run build`。

## 写入被业务层拒绝

HTTP `200` 不代表设置一定保存成功。检查 JSON 响应中的 `result.error`，并对照命名空间 schema、字段类型、revision 与插件 validator。`exposeAllSettingsNamespaces` 只移除代理 allowlist，不放宽业务校验。

## WebSocket 重连

检查代理是否支持并转发 Upgrade/Connection 头，以及 `/api/events.mux`、`/api/events.host` 是否使用与页面相同的 Host 和 Origin。不要为修复重连而关闭外层可信请求栅栏。

## Shell 沙箱后端不可用

该错误来自 Harness 的本地进程沙箱，与 `trustedHosts`、特权 RPC、设置命名空间和远程设置持久化无关。Linux 后端按以下顺序进行功能探测：

```text
bwrap -> Landlock -> 拒绝无沙箱执行
```

Harness 会缓存本次插件生命周期内的 runner 选择。安装、移除或修复后端后必须重启 Harness，才能重新探测。

### 优先配置 bwrap

普通 Linux 服务器建议优先使用官方首选的 Bubblewrap：

```bash
apt-get update
apt-get install -y bubblewrap

bwrap \
  --ro-bind / / \
  --dev /dev \
  --proc /proc \
  --die-with-parent \
  -- true
```

最后一条命令退出码为 `0` 时，Harness 可以选择 bwrap。按原部署方式停止并重新启动 `dsh web` 后生效。

不要只用 `bwrap --version` 判断可用性；版本输出不能证明当前宿主允许它创建并配置实际沙箱。

### bwrap 已安装但返回 Operation not permitted

这通常是容器或宿主安全策略限制，不代表所有机器都无法使用 bwrap。常见限制包括：

- 不允许 user namespace 内创建 mount namespace。
- AppArmor、SELinux 或容器 runtime 拒绝挂载传播、bind mount、`/proc`、`/dev` 或 tmpfs 操作。
- 容器 capability bounding set 不包含部署方式需要的能力。
- Kubernetes `securityContext` 或宿主 sysctl 禁止相关 namespace 操作。

可收集以下诊断信息：

```bash
unshare --user --map-root-user true
unshare --user --map-root-user --mount true

grep -E 'Cap(Inh|Prm|Eff|Bnd|Amb)|NoNewPrivs|Seccomp' /proc/self/status
cat /proc/self/attr/current 2>/dev/null || true
sysctl kernel.unprivileged_userns_clone 2>/dev/null || true
sysctl kernel.apparmor_restrict_unprivileged_userns 2>/dev/null || true
```

若单独 user namespace 成功、user + mount namespace 失败，需由宿主平台放行兼容的 namespace 与 LSM 策略。优先请求平台提供适用于 rootless bwrap 的 user/mount namespace 和 AppArmor/SELinux 配置；`CAP_SYS_ADMIN` 或 privileged 容器是权限更大的替代方案，不应作为默认建议。容器内部通常无法修改宿主只读 sysctl 或 LSM profile。

### bwrap 不可用时使用 Landlock

Landlock 是 Harness 官方 Linux 回退后端，不依赖 mount namespace。通过 npm 安装的 Harness 会随平台包提供 launcher；源码 checkout 中的 `packages/linux-<arch>/bin/landlock-run` 被 Git 忽略，可能需要本机编译：

```bash
apt-get update
apt-get install -y musl-tools

export PATH=/data/miniconda/envs/deepseek-harness/bin:$PATH
pnpm --dir /data/deepseek-harness/native/landlock-run run build:native
```

验证 x64 launcher；arm64 将路径中的 `linux-x64` 改为 `linux-arm64`：

```bash
/data/deepseek-harness/native/landlock-run/packages/linux-x64/bin/landlock-run --probe
```

可接受结果：

```text
landlock: fully enforced
```

或：

```text
landlock: partially enforced (older ABI)
```

`partial` 表示较旧内核 ABI 只能约束其支持的访问类别，不表示沙箱未启用。`unusable`、非零退出码或 launcher 不存在表示该后端不可用。

运行 Harness 自带的真实隔离测试：

```bash
cd /data/deepseek-harness

pnpm exec vitest run --config vitest.e2e.config.ts \
  packages/sandbox/sandbox-local/tests/landlock.e2e.ts

pnpm exec vitest run --config vitest.e2e.config.ts \
  packages/shell/bash-sandbox/tests/landlock.e2e.ts
```

修复后重启 Harness，使 `dsh-sandbox-local` 清除已缓存的 `unavailable` 结论。若自定义了 `TMPDIR`，还要确保它属于当前沙箱策略允许写入的路径；支持版本的 Linux workspace-write profile 默认放行 `/tmp` 和 workspace root。

不要为绕过 `SANDBOX_UNAVAILABLE` 而把默认权限永久改成 `danger-full-access`。这会取消对应命令的沙箱保护，而不是修复后端。

## 测试与构建 warning

任何非零退出码都表示失败。只有在测试或构建退出码为 `0` 时，已知的可选架构不支持提示、Vite migration/dependency hint 和 chunk-size warning 才可接受，并应记录到验证日志；新的 error、失败测试或构建失败不能忽略。构建会创建 ignored/generated artifacts，这是正常现象；稳定性比较只针对 Git 跟踪的源码 diff，不把整个工作树或生成产物声明为不可变。
