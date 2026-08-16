# 版本兼容性

支持的上游 commit：`47f943859bef60e4160492346772ded9b24f765a`。

本仓库只维护一个面向该 commit 的源码补丁，不承诺补丁可应用到其他分支、tag 或 commit。

`scripts/verify.sh` 对非支持 HEAD 直接退出 `1`，并打印支持 commit 与实际 commit。即使 `git apply --check` 在其他版本碰巧成功，也不能视为本仓库验证通过；必须将测试过的行为移植到新版本、重新生成补丁并更新所有内容身份记录。

## 为什么源码补丁会漂移

Git patch 依赖目标文件路径和周边文本。上游重命名文件、调整导入、修改配置 schema、重构请求栅栏或测试 fixture 后，即使目标行为仍相似，补丁 hunk 也可能不再匹配。能够勉强应用也不代表语义仍正确，因此 commit 不同时必须重新验证三层控制和安全默认值。

## 应用前检查

```bash
git -C /data/deepseek-harness checkout 47f943859bef60e4160492346772ded9b24f765a
git -C /data/deepseek-harness apply --check /path/to/public-access-kit/patches/public-access.patch
```

`git apply --check` 不修改文件。检查失败时不要使用宽松参数强行套用；应在新的隔离 checkout 中移植行为并重新生成补丁。

只读辅助检查：

```bash
/path/to/public-access-kit/scripts/verify.sh /data/deepseek-harness
```

## 刷新补丁

从补丁仓库根目录运行以下命令。先通过环境变量提供拟支持的新 commit，然后创建两个干净 checkout：

```bash
PATCH_KIT=$(pwd -P)
: "${NEW_COMMIT:?export NEW_COMMIT as the upstream commit being evaluated}"

git clone https://github.com/deepseek-ai/deepseek-harness.git /tmp/dsh-old
git clone https://github.com/deepseek-ai/deepseek-harness.git /tmp/dsh-new
git -C /tmp/dsh-old checkout 47f943859bef60e4160492346772ded9b24f765a
git -C /tmp/dsh-new checkout "$NEW_COMMIT"
git -C /tmp/dsh-old status --short
git -C /tmp/dsh-new status --short
```

两个 `status --short` 命令都必须没有输出。在旧 checkout 检查并应用当前补丁，得到经过现有测试定义的行为参考：

```bash
git -C /tmp/dsh-old apply --check "$PATCH_KIT/patches/public-access.patch"
git -C /tmp/dsh-old apply "$PATCH_KIT/patches/public-access.patch"
```

然后把旧 checkout 中经过测试的三项控制及相关生产配置转发、依赖和测试改动移植到 `/tmp/dsh-new`。保持 `pinPrivilegedToLoopback`、`exposeAllSettingsNamespaces`、`allowRemoteSettingsPersistence` 的默认值分别为 `true`、`false`、`false`，保留外层 Host/Origin/`Sec-Fetch-Site` 栅栏，并确认未绕过命名空间注册、schema 或插件 validator。

在 `/tmp/dsh-new` 完成下文全部测试与构建后，从新 commit 对批准的 12 个文件重新生成补丁：

```bash
git -C /tmp/dsh-new diff --binary "$NEW_COMMIT" -- \
  packages/client/connection/src/index.ts \
  packages/client/connection/tests/node-half.host.spec.ts \
  packages/client/ui-settings/package.json \
  packages/client/ui-settings/src/client/index.ts \
  packages/client/ui-settings/src/client/settings-scope.ts \
  packages/client/ui-settings/tests/plugin.client.spec.ts \
  packages/client/ui-settings/tests/settings-scope.client.spec.ts \
  packages/host/apiproxy/src/api-proxy.ts \
  packages/host/apiproxy/src/index.ts \
  packages/host/apiproxy/tests/api-proxy-config.spec.ts \
  packages/host/apiproxy/tests/session-export.spec.ts \
  pnpm-lock.yaml \
  > "$PATCH_KIT/patches/public-access.patch"
```

在另一个干净的新 commit checkout 上重新运行 `git apply --check`，再应用补丁并重复全部验证。只有这些检查都通过后，才更新 README、验证脚本和本文中的支持 commit。

## 必须验证

聚焦测试文件：

```text
packages/client/connection/tests/node-half.host.spec.ts
packages/client/ui-settings/tests/plugin.client.spec.ts
packages/client/ui-settings/tests/settings-scope.client.spec.ts
packages/host/apiproxy/tests/api-proxy-config.spec.ts
packages/host/apiproxy/tests/session-export.spec.ts
```

运行命令：

```bash
pnpm exec vitest run \
  packages/client/connection/tests/node-half.host.spec.ts \
  packages/client/ui-settings/tests/plugin.client.spec.ts \
  packages/client/ui-settings/tests/settings-scope.client.spec.ts \
  packages/host/apiproxy/tests/api-proxy-config.spec.ts \
  packages/host/apiproxy/tests/session-export.spec.ts
pnpm run test:gui
pnpm run build
```

更新支持 commit 前，五个聚焦测试、`pnpm run test:gui` 和完整 `pnpm run build` 都必须以退出码 `0` 成功。任何非零退出码都失败；仅当退出码为 `0` 时，已知的可选架构不支持提示、Vite migration/dependency hint 和 chunk-size warning 可被记录后接受，新的 error 或失败不能忽略。还应重复正确 Origin 返回 `200`、错误 Origin 返回 `403` 的运行时冒烟测试。

验证记录必须包含：HEAD、应用前 clean `git status --short`、补丁 SHA256、稳定 patch ID、排序后的精确 12 文件 manifest、`applicable` 与 `already-applied` 两种状态、Node/pnpm 版本、安装/测试/构建退出码和测试计数。构建会生成 ignored/generated artifacts；只比较 Git 跟踪的源码 diff 在构建前后是否稳定，不声称生成产物不可变。更新任何仓库文件后还必须重新生成并检查 `SHA256SUMS`。现有证据见 [`validation.md`](validation.md)。
