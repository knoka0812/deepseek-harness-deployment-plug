# 最终验证证据

本页记录在第二个 Linux DeepSeek Harness checkout 上完成的最终验证。目标 checkout 固定在支持 commit；这些结果是一次可复现的人工验证记录，不是签名、透明日志或加密 CI attestation。

## 环境与身份

| 项目 | 结果 |
| --- | --- |
| DeepSeek Harness HEAD | `47f943859bef60e4160492346772ded9b24f765a` |
| Node.js | `v24.19.0` |
| pnpm | `11.7.0` |
| patch SHA256 | `00c49c14460c581a8695f3053fe39c3693b6fc754f6edcb1e627fddb1ec225ef` |
| stable patch ID | `4698e67e76e2cbdee4cd4e5bd55c2db5c8cbb491` |
| patch manifest | 精确 12 个批准路径 |

补丁 12 路径为：

```text
packages/client/connection/src/index.ts
packages/client/connection/tests/node-half.host.spec.ts
packages/client/ui-settings/package.json
packages/client/ui-settings/src/client/index.ts
packages/client/ui-settings/src/client/settings-scope.ts
packages/client/ui-settings/tests/plugin.client.spec.ts
packages/client/ui-settings/tests/settings-scope.client.spec.ts
packages/host/apiproxy/src/api-proxy.ts
packages/host/apiproxy/src/index.ts
packages/host/apiproxy/tests/api-proxy-config.spec.ts
packages/host/apiproxy/tests/session-export.spec.ts
pnpm-lock.yaml
```

## 结果

| 步骤 | 结果 |
| --- | --- |
| 应用前 `git status --short` | clean，无输出 |
| verifier `applicable` | exit `0`，stderr `0` 行 |
| verifier `already-applied` | exit `0`，stderr `0` 行 |
| `pnpm install --frozen-lockfile` | exit `0` |
| 五文件聚焦测试 | exit `0`；5 files passed，101 tests passed |
| `pnpm run test:gui` | exit `0`；271 files passed、1 file skipped；3758 tests passed、4 tests skipped |
| `pnpm run build` | exit `0`；Vite transformed 413 modules；built in 3.41s |
| repository diff check | passed |
| patch manifest | exactly 12 paths |
| prohibited identifier scan | 0 matches |

`applicable` 与 `already-applied` 两次 verifier 调用都没有 stderr 输出。完整构建会创建 ignored/generated artifacts；验证只确认 Git 跟踪的源码 diff 在测试和构建前后保持稳定，不声称 ignored 构建产物或整个工作树不可变。

## Warning 策略

任何安装、测试或构建命令的非零退出码都失败。仅在对应命令退出码为 `0` 时，已知的可选架构不支持提示、Vite migration/dependency hint 和 chunk-size warning 可以记录后接受。新的 error、失败测试、未解释的异常或非零退出码不能忽略。

## 复现命令

从补丁包根目录设置路径，并在干净 Linux checkout 中记录身份：

```bash
PATCH_KIT=$(pwd -P)
TARGET=/tmp/deepseek-harness-public-access-validation

git clone https://github.com/deepseek-ai/deepseek-harness.git "$TARGET"
git -C "$TARGET" checkout 47f943859bef60e4160492346772ded9b24f765a
git -C "$TARGET" rev-parse HEAD
git -C "$TARGET" status --short
node --version
pnpm --version
sha256sum "$PATCH_KIT/patches/public-access.patch"
git patch-id --stable < "$PATCH_KIT/patches/public-access.patch"
awk '/^diff --git a\// { path=$3; sub(/^a\//, "", path); print path }' \
  "$PATCH_KIT/patches/public-access.patch" | LC_ALL=C sort
```

验证适用状态，应用，再验证已应用状态：

```bash
"$PATCH_KIT/scripts/verify.sh" "$TARGET"
git -C "$TARGET" apply "$PATCH_KIT/patches/public-access.patch"
"$PATCH_KIT/scripts/verify.sh" "$TARGET"
```

安装、五文件聚焦测试、GUI 测试和完整构建：

```bash
pnpm --dir "$TARGET" install --frozen-lockfile
pnpm --dir "$TARGET" exec vitest run \
  packages/client/connection/tests/node-half.host.spec.ts \
  packages/client/ui-settings/tests/plugin.client.spec.ts \
  packages/client/ui-settings/tests/settings-scope.client.spec.ts \
  packages/host/apiproxy/tests/api-proxy-config.spec.ts \
  packages/host/apiproxy/tests/session-export.spec.ts
pnpm --dir "$TARGET" run test:gui
pnpm --dir "$TARGET" run build
```

记录构建前后的 tracked source diff，并检查补丁包：

```bash
git -C "$TARGET" diff --binary > /tmp/tracked-before.diff
pnpm --dir "$TARGET" run build
git -C "$TARGET" diff --binary > /tmp/tracked-after.diff
cmp /tmp/tracked-before.diff /tmp/tracked-after.diff

git diff --check
git diff --cached --check
sha256sum -c SHA256SUMS
```

禁止标识符扫描应返回 0 个匹配。记录命令版本、每一步退出码、测试文件/测试数量以及 stderr 行数，避免只保留摘要性“通过”结论。
