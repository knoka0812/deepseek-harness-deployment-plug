#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PATCH="$ROOT/patches/public-access.patch"
OVERLAY="$ROOT/config/cordis.public-access.yml"
SUPPORTED_COMMIT=47f943859bef60e4160492346772ded9b24f765a
EXPECTED_PATCH_SHA256=00c49c14460c581a8695f3053fe39c3693b6fc754f6edcb1e627fddb1ec225ef

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /path/to/deepseek-harness" >&2
  exit 2
fi

TARGET=$1
if ! git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "usage: $0 /path/to/deepseek-harness" >&2
  exit 2
fi

patch_section_contains() {
  local path=$1
  local needle=$2
  awk -v header="diff --git a/$path b/$path" -v needle="$needle" '
    /^diff --git / { active = ($0 == header) }
    active && index($0, needle) { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$PATCH"
}

overlay_row_has_exact_value() {
  local id=$1
  local key=$2
  local expected=$3
  awk -v id="$id" -v key="$key" -v expected="$expected" '
    /^- id: / { row = $3 }
    index($0, key) {
      count++
      if (row != id || $0 != expected) bad = 1
    }
    END { exit count == 1 && !bad ? 0 : 1 }
  ' "$OVERLAY"
}

actual=$(git -C "$TARGET" rev-parse HEAD)
if [[ "$actual" != "$SUPPORTED_COMMIT" ]]; then
  echo "error: unsupported target commit" >&2
  echo "supported: $SUPPORTED_COMMIT" >&2
  echo "actual:    $actual" >&2
  exit 1
fi

if ! command -v sha256sum >/dev/null 2>&1; then
  echo "error: sha256sum is required to verify the patch" >&2
  exit 1
fi
actual_patch_sha256=$(sha256sum "$PATCH" | awk '{ print $1 }')
if [[ "$actual_patch_sha256" != "$EXPECTED_PATCH_SHA256" ]]; then
  echo "error: patch SHA256 mismatch" >&2
  echo "expected: $EXPECTED_PATCH_SHA256" >&2
  echo "actual:   $actual_patch_sha256" >&2
  exit 1
fi

expected_manifest=$(cat <<'EOF'
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
EOF
)
actual_manifest=$(awk '/^diff --git a\// {
  path = $3
  sub(/^a\//, "", path)
  print path
}' "$PATCH" | LC_ALL=C sort)
if [[ "$actual_manifest" != "$expected_manifest" ]]; then
  echo "error: patch manifest does not match the expected 12 paths" >&2
  echo "expected manifest:" >&2
  printf '%s\n' "$expected_manifest" >&2
  echo "actual manifest:" >&2
  printf '%s\n' "$actual_manifest" >&2
  exit 1
fi

if forward_diagnostics=$(git -C "$TARGET" apply --check "$PATCH" 2>&1); then
  state=applicable
elif reverse_diagnostics=$(git -C "$TARGET" apply --reverse --check "$PATCH" 2>&1); then
  state=already-applied
else
  echo "error: patch is neither applicable nor already applied" >&2
  echo "forward check:" >&2
  printf '%s\n' "$forward_diagnostics" >&2
  echo "reverse check:" >&2
  printf '%s\n' "$reverse_diagnostics" >&2
  exit 1
fi

if ! patch_section_contains packages/client/connection/src/index.ts pinPrivilegedToLoopback; then
  echo "error: connection source diff does not contain pinPrivilegedToLoopback" >&2
  exit 1
fi
if ! patch_section_contains packages/host/apiproxy/src/index.ts exposeAllSettingsNamespaces \
  && ! patch_section_contains packages/host/apiproxy/src/api-proxy.ts exposeAllSettingsNamespaces; then
  echo "error: API proxy source diffs do not contain exposeAllSettingsNamespaces" >&2
  exit 1
fi
if ! patch_section_contains packages/client/ui-settings/src/client/settings-scope.ts 'allowRemoteSettingsPersistence: z.boolean().default(true)'; then
  echo "error: settings scope source diff must default browser remote persistence to true" >&2
  exit 1
fi
if ! patch_section_contains packages/client/ui-settings/src/client/index.ts SettingsScopeBinderConfig \
  || ! patch_section_contains packages/client/ui-settings/src/client/index.ts 'new SettingsScopeBinder(ctx, config)'; then
  echo "error: production client entry diff does not forward settings scope config" >&2
  exit 1
fi

if ! overlay_row_has_exact_value webserver 'host:' "    host: '0.0.0.0'"; then
  echo "error: webserver overlay row must contain host: '0.0.0.0' exactly once" >&2
  exit 1
fi
if ! overlay_row_has_exact_value connection 'pinPrivilegedToLoopback:' '    pinPrivilegedToLoopback: false'; then
  echo "error: connection overlay row must disable pinPrivilegedToLoopback exactly once" >&2
  exit 1
fi
if ! overlay_row_has_exact_value api-gateway 'exposeAllSettingsNamespaces:' '    exposeAllSettingsNamespaces: true'; then
  echo "error: api-gateway overlay row must enable exposeAllSettingsNamespaces exactly once" >&2
  exit 1
fi
if ! overlay_row_has_exact_value ui-settings 'allowRemoteSettingsPersistence:' '    allowRemoteSettingsPersistence: true'; then
  echo "error: ui-settings overlay row must enable allowRemoteSettingsPersistence exactly once" >&2
  exit 1
fi

echo "patch state: $state"
echo "focused tests:"
echo "  pnpm exec vitest run packages/client/connection/tests/node-half.host.spec.ts packages/client/ui-settings/tests/plugin.client.spec.ts packages/client/ui-settings/tests/settings-scope.client.spec.ts packages/host/apiproxy/tests/api-proxy-config.spec.ts packages/host/apiproxy/tests/session-export.spec.ts"
echo "build:"
echo "  pnpm run build"
