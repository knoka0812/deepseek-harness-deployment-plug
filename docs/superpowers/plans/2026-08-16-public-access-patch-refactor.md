# Public Access Patch Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild this repository as a focused patch kit that enables complete trusted-host Web UI access, exposes every registered settings namespace, and permits Host-backed settings persistence from remote pages while retaining safe upstream defaults.

**Architecture:** Make three narrowly scoped, opt-in changes to DeepSeek Harness and distribute them as one `patches/public-access.patch`. A Cordis overlay enables the three options and binds the Web server to all interfaces; documentation and a read-only verification script explain and validate the patch without turning this repository into an installer.

**Tech Stack:** Git patches, TypeScript, Vitest, Cordis YAML patch overlays, Bash, DeepSeek Harness commit `47f943859bef60e4160492346772ded9b24f765a`.

---

## File Map

Repository files after implementation:

- Create: `patches/public-access.patch` - one patch containing all upstream source and test changes.
- Create: `config/cordis.public-access.yml` - explicit public-access Cordis overlay.
- Create: `scripts/verify.sh` - read-only patch compatibility checker.
- Create: `docs/architecture.md` - three-control root-cause and data-flow explanation.
- Create: `docs/security.md` - threat model and deployment mitigations.
- Create: `docs/troubleshooting.md` - symptom-to-layer diagnosis.
- Create: `docs/version-compatibility.md` - supported upstream commit and patch refresh workflow.
- Create: `docs/validation.md` - final supported-checkout evidence and reproduction procedure.
- Modify: `README.md` - concise entry point and manual application workflow.
- Create: `LICENSE` - repository license.
- Create: `THIRD_PARTY_NOTICES.md` - upstream MIT notice for derived patch content.
- Create: `SHA256SUMS` - hashes for every shipped file except the manifest itself.
- Delete: `pinPrivilegedToLoopback.patch` - replaced by the combined patch.
- Delete: `cordis.yml` - replaced by `config/cordis.public-access.yml`.
- Delete: `cordis.example.yml` - no second drifting overlay.
- Delete: `dsh-start.sh` - repository no longer owns runtime process management.

Temporary upstream checkout changes used to generate the patch:

- Modify: `packages/client/connection/src/index.ts`
- Modify: `packages/client/connection/tests/node-half.host.spec.ts`
- Modify: `packages/client/ui-settings/package.json`
- Modify: `packages/client/ui-settings/src/client/index.ts`
- Modify: `packages/client/ui-settings/src/client/settings-scope.ts`
- Modify: `packages/client/ui-settings/tests/plugin.client.spec.ts`
- Modify: `packages/client/ui-settings/tests/settings-scope.client.spec.ts`
- Modify: `packages/host/apiproxy/src/index.ts`
- Modify: `packages/host/apiproxy/src/api-proxy.ts`
- Modify: `packages/host/apiproxy/tests/api-proxy-config.spec.ts`
- Modify: `packages/host/apiproxy/tests/session-export.spec.ts`
- Modify: `pnpm-lock.yaml`

The production client entry forwards the new configuration into the binder. The client manifest and lockfile add the Schemastery runtime dependency needed by the exported schema. The client plugin and API proxy session-export tests assert production configuration forwarding and integration of the new safe schema defaults.

Do not commit during execution unless the user explicitly requests commits.

### Task 1: Prepare a Clean Supported Upstream Checkout

**Files:**
- Verify: temporary DeepSeek Harness checkout at commit `47f943859bef60e4160492346772ded9b24f765a`

- [ ] **Step 1: Create an isolated upstream checkout**

Use a temporary path outside this patch repository. On the Linux validation host:

```bash
git clone https://github.com/deepseek-ai/deepseek-harness.git /data/deepseek-harness-public-access-patch-source
git -C /data/deepseek-harness-public-access-patch-source checkout 47f943859bef60e4160492346772ded9b24f765a
```

Expected: checkout succeeds and reports a detached HEAD at the supported commit.

- [ ] **Step 2: Verify the checkout is clean**

Run:

```bash
git -C /data/deepseek-harness-public-access-patch-source status --short
git -C /data/deepseek-harness-public-access-patch-source rev-parse HEAD
```

Expected:

```text
47f943859bef60e4160492346772ded9b24f765a
```

The status command must print nothing.

- [ ] **Step 3: Install the existing lockfile dependencies**

Run:

```bash
export PATH=/data/miniconda/envs/deepseek-harness/bin:$PATH
pnpm --dir /data/deepseek-harness-public-access-patch-source install --frozen-lockfile
```

Expected: exit code `0`.

### Task 2: Make Privileged RPC Loopback Pin Configurable

**Files:**
- Modify: temporary upstream `packages/client/connection/src/index.ts`
- Test: temporary upstream `packages/client/connection/tests/node-half.host.spec.ts`

- [ ] **Step 1: Add a failing trusted-host privileged-method test**

Extend the test helper config type:

```ts
async function mounted(config?: {
  trustedHosts?: string[]
  pinPrivilegedToLoopback?: boolean
}): Promise<{
  routes: WebRoute[]
  upgrades: WebUpgradeRoute[]
  dispose: () => Promise<void>
}> {
```

Add this test before the existing declared-authority pass-through test:

```ts
it('lets a declared trusted authority reach privileged methods when the loopback pin is off', async () => {
  const { routes, dispose } = await mounted({
    trustedHosts: ['harness.example'],
    pinPrivilegedToLoopback: false,
  })
  for (const method of [
    'host.pickDirectory', 'host.openPath',
    'settings.describe', 'settings.openDocument', 'settings.update', 'settings.replace', 'settings.mutate',
    'credentials.describe', 'credentials.set', 'credentials.unset',
    'llm.discoverModels',
    'agentPreset.read', 'agentPreset.copy', 'agentPreset.openDocument', 'agentPreset.remove',
  ]) {
    const response = fakeResponse()
    await routes[0]!.handler(
      fakeRequest({ host: 'harness.example' }, `${API_PATH}/${method}`),
      response.response,
    )
    expect(response.state.status).toBe(404)
  }

  const denied = fakeResponse()
  await routes[0]!.handler(
    fakeRequest({ host: 'other.example' }, `${API_PATH}/settings.describe`),
    denied.response,
  )
  expect(denied.state.status).toBe(403)
  await dispose()
})
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
export PATH=/data/miniconda/envs/deepseek-harness/bin:$PATH
pnpm --dir /data/deepseek-harness-public-access-patch-source exec vitest run \
  packages/client/connection/tests/node-half.host.spec.ts
```

Expected: FAIL because `pinPrivilegedToLoopback` is not part of the connection config and the privileged requests remain `403`.

- [ ] **Step 3: Add the safe-default configuration switch**

In `packages/client/connection/src/index.ts`, extend `ConnectionConfig`:

```ts
/**
 * Whether privileged methods stay loopback-only even for declared trusted
 * hosts. Disable only for an explicitly anonymous remote administration
 * deployment; the outer trusted-host request fence remains active.
 */
pinPrivilegedToLoopback?: boolean
```

Extend the schema:

```ts
export const Config: z<ConnectionConfig> = z.object({
  trustedHosts: z.array(String).default([]),
  maxRequestBodyBytes: z.natural().min(1).default(DEFAULT_MAX_REQUEST_BODY_BYTES),
  pinPrivilegedToLoopback: z.boolean().default(true),
})
```

Read the default inside `apply`:

```ts
const pinPrivilegedToLoopback = config?.pinPrivilegedToLoopback ?? true
```

Guard the second privileged check:

```ts
if (pinPrivilegedToLoopback
  && method !== undefined
  && PRIVILEGED_METHODS.has(method)
  && !isTrustedApiRequest(request, [])) {
  return new Response('forbidden', { status: 403 })
}
```

- [ ] **Step 4: Run the focused test**

Run the command from Step 2.

Expected: PASS, including the new trusted-host test and existing default-safe tests.

### Task 3: Make Registered Settings Namespace Exposure Configurable

**Files:**
- Modify: temporary upstream `packages/host/apiproxy/src/index.ts`
- Modify: temporary upstream `packages/host/apiproxy/src/api-proxy.ts`
- Test: temporary upstream `packages/host/apiproxy/tests/api-proxy-config.spec.ts`
- Test: temporary upstream `packages/host/apiproxy/tests/session-export.spec.ts`

- [ ] **Step 1: Add a failing API proxy test for all registered namespaces**

Add this test near the existing settings exposure tests:

```ts
it('exposes every registered namespace when configured without accepting unregistered namespaces', async () => {
  const ctx = await harness()
  ctx.settings.register(settingsNamespace('third-party-plugin'), z.object({
    enabled: z.boolean().default(false),
  }))
  const api = createApiProxy(ctx, {
    ...DEFAULTS,
    exposeAllSettingsNamespaces: true,
  })

  expect(expectOk(await api.settings.describe(request({}))).namespaces.map(view => view.ns))
    .toContain('third-party-plugin')

  const updated = expectOk(await api.settings.update(request({
    ns: 'third-party-plugin',
    patch: { enabled: true },
  })))
  expect(updated.value).toEqual({ enabled: true })

  const unknown = expectErr(await api.settings.update(request({
    ns: 'not-registered',
    patch: {},
  })))
  expect(unknown.code).toBe('settings-rejected')
})
```

- [ ] **Step 2: Run the API proxy test and verify it fails**

Run:

```bash
export PATH=/data/miniconda/envs/deepseek-harness/bin:$PATH
pnpm --dir /data/deepseek-harness-public-access-patch-source exec vitest run \
  packages/host/apiproxy/tests/api-proxy-config.spec.ts
```

Expected: FAIL because `ApiProxyDefaults` has no `exposeAllSettingsNamespaces` property and the third-party namespace remains filtered.

- [ ] **Step 3: Add the API proxy plugin configuration**

In `packages/host/apiproxy/src/index.ts`, extend `Config`:

```ts
/**
 * Expose every namespace already registered with the Host settings provider.
 * This does not create namespaces or bypass their schemas and validators.
 */
exposeAllSettingsNamespaces?: boolean
```

Extend `ApiProxyService.Config`:

```ts
static Config: z<Config> = z.object({
  nativeOpen: z.boolean(),
  exposeAllSettingsNamespaces: z.boolean().default(false),
  sessionExportCompressionLevel: z.number().step(1).min(0).max(9)
    .default(DEFAULT_SESSION_LOG_COMPRESSION_LEVEL) as z<SessionLogCompressionLevel>,
  coldBlankProbeMaxBytes: z.natural().default(DEFAULT_COLD_BLANK_PROBE_MAX_BYTES),
})
```

Pass the setting into `createApiProxy`:

```ts
const api = createApiProxy(ctx, {
  defaultModelSelection: () => ctx.agentDefaultModel.currentSelection(),
  saveDefaultModelSelection: selection => ctx.agentDefaultModel.saveSelection(selection),
  cwd: process.cwd(),
  exposeAllSettingsNamespaces: config.exposeAllSettingsNamespaces ?? false,
  ...config.nativeOpen === undefined ? {} : { canOpenPath: () => config.nativeOpen as boolean },
  ...(config.sessionExportCompressionLevel === undefined
    ? {}
    : { sessionExportCompressionLevel: config.sessionExportCompressionLevel }),
  ...(config.coldBlankProbeMaxBytes === undefined
    ? {}
    : { coldBlankProbeMaxBytes: config.coldBlankProbeMaxBytes }),
})
```

- [ ] **Step 4: Implement the exposure switch in the API proxy**

Extend `ApiProxyDefaults` in `packages/host/apiproxy/src/api-proxy.ts`:

```ts
/** Expose every namespace registered with the composed settings provider. */
exposeAllSettingsNamespaces?: boolean
```

Change the write guard in `settingsWrite`:

```ts
if (defaults.exposeAllSettingsNamespaces !== true && !exposedNamespaces().has(ns)) {
  return notExposed(request, ns)
}
```

Change the `settings.describe` filter:

```ts
namespaces: settings.describe({ redactSecrets: true })
  .filter(descriptor => defaults.exposeAllSettingsNamespaces === true
    || exposed.has(String(descriptor.ns)))
  .map(namespaceView),
```

This intentionally lets the settings provider produce `settings-rejected` for an unregistered namespace instead of claiming that a configured expose-all proxy recognizes it.

- [ ] **Step 5: Run the focused API proxy tests**

Run the command from Step 2.

Expected: PASS, including existing default allowlist tests and the new expose-all test.

Update `session-export.spec.ts` default-schema assertions to include `exposeAllSettingsNamespaces: false`. This verifies that the new safe default is present when the API gateway schema composes with the existing session export and cold blank probe defaults.

### Task 4: Make Remote Host Settings Persistence Configurable

**Files:**
- Modify: temporary upstream `packages/client/ui-settings/package.json`
- Modify: temporary upstream `packages/client/ui-settings/src/client/index.ts`
- Modify: temporary upstream `packages/client/ui-settings/src/client/settings-scope.ts`
- Test: temporary upstream `packages/client/ui-settings/tests/plugin.client.spec.ts`
- Test: temporary upstream `packages/client/ui-settings/tests/settings-scope.client.spec.ts`
- Modify: temporary upstream `pnpm-lock.yaml`

- [ ] **Step 1: Preserve the existing safe-default test**

Keep the existing test that provides `isLoopback: false`, starts `SettingsScopeBinder` without configuration, and expects:

```ts
expect(scope.getSnapshot()).toMatchObject({
  status: 'unavailable',
  mode: 'memory',
  writable: false,
})
expect(describeCall).not.toHaveBeenCalled()
```

This proves the new switch does not silently change upstream behavior.

- [ ] **Step 2: Add a failing opt-in remote Host-mode test**

Add this test after the safe-default remote-browser test:

```ts
it('binds a remote browser to Host settings when remote persistence is enabled', async () => {
  const describeCall = vi.fn().mockResolvedValueOnce(described({ preference: 'dark' }, 1))
  const ctx = new Context()
  ctx.provide('connection', {
    api: { settings: { describe: describeCall } },
    isLoopback: false,
  } as never)
  let scope!: SettingsScope<UiTestSettings>
  new TestRemote(ctx)
  await ctx.plugin(SettingsScopeBinder, {
    allowRemoteSettingsPersistence: true,
  }).await()
  const fiber = ctx.plugin({
    inject: ['connection', 'remote', 'settingsScope'],
    apply: (plugin: Context) => {
      scope = plugin.settingsScope.bind<UiTestSettings>({ namespace: 'ui-test' })
    },
  })
  await fiber.await()

  expect(describeCall).toHaveBeenCalledOnce()
  expect(scope.getSnapshot()).toMatchObject({
    status: 'ready',
    mode: 'host',
    value: { preference: 'dark' },
    revision: 1,
    writable: true,
  })
  await fiber.dispose()
})
```

- [ ] **Step 3: Run the settings scope test and verify it fails**

Run:

```bash
export PATH=/data/miniconda/envs/deepseek-harness/bin:$PATH
pnpm --dir /data/deepseek-harness-public-access-patch-source exec vitest run \
  packages/client/ui-settings/tests/settings-scope.client.spec.ts
```

Expected: FAIL because `SettingsScopeBinder` does not accept `allowRemoteSettingsPersistence` and still selects memory mode.

- [ ] **Step 4: Add the safe-default binder configuration**

In `packages/client/ui-settings/src/client/settings-scope.ts`, add:

```ts
import z from '@deepseek-ai/schemastery'
```

Define the config before `SettingsScopeBinder`:

```ts
export interface Config {
  /** Use Host-backed settings sync for non-loopback browser pages. */
  allowRemoteSettingsPersistence?: boolean
}
```

Update the service class:

```ts
export class SettingsScopeBinder extends Service {
  static Config: z<Config> = z.object({
    allowRemoteSettingsPersistence: z.boolean().default(false),
  })

  constructor(ctx: Context, private readonly config: Config) {
    super(ctx, 'settingsScope')
  }
```

Update controller construction:

```ts
const controller = new SettingsScopeController<T>(
  connection.api,
  spec,
  connection.isLoopback || this.config.allowRemoteSettingsPersistence === true
    ? 'host'
    : 'memory',
)
```

- [ ] **Step 5: Run the focused settings scope tests**

Run the command from Step 3.

Expected: PASS for both default remote memory mode and configured remote Host mode.

The production plugin entry must also forward `allowRemoteSettingsPersistence` to the binder. Export its Schemastery-backed config, declare `@deepseek-ai/schemastery` as a runtime dependency, update `pnpm-lock.yaml`, and cover the production entry in `plugin.client.spec.ts` so the overlay configuration is exercised through the real plugin API.

### Task 5: Generate the Single Public Access Patch

**Files:**
- Create: `patches/public-access.patch`

- [ ] **Step 1: Verify only the 12 intended upstream files changed**

Run:

```bash
git -C /data/deepseek-harness-public-access-patch-source status --short
```

Expected paths:

```text
packages/client/connection/src/index.ts
packages/client/connection/tests/node-half.host.spec.ts
packages/client/ui-settings/package.json
packages/client/ui-settings/src/client/index.ts
packages/client/ui-settings/src/client/settings-scope.ts
packages/client/ui-settings/tests/plugin.client.spec.ts
packages/client/ui-settings/tests/settings-scope.client.spec.ts
packages/host/apiproxy/src/index.ts
packages/host/apiproxy/src/api-proxy.ts
packages/host/apiproxy/tests/api-proxy-config.spec.ts
packages/host/apiproxy/tests/session-export.spec.ts
pnpm-lock.yaml
```

- [ ] **Step 2: Run all five focused test files together**

Run:

```bash
export PATH=/data/miniconda/envs/deepseek-harness/bin:$PATH
pnpm --dir /data/deepseek-harness-public-access-patch-source exec vitest run \
  packages/client/connection/tests/node-half.host.spec.ts \
  packages/client/ui-settings/tests/plugin.client.spec.ts \
  packages/client/ui-settings/tests/settings-scope.client.spec.ts \
  packages/host/apiproxy/tests/api-proxy-config.spec.ts \
  packages/host/apiproxy/tests/session-export.spec.ts
```

Expected: all test files pass.

- [ ] **Step 3: Generate the patch from the supported commit**

Create `patches/` in this repository, then run from the upstream checkout:

```bash
git -C /data/deepseek-harness-public-access-patch-source diff --binary \
  47f943859bef60e4160492346772ded9b24f765a -- \
  packages/client/connection/src/index.ts \
  packages/client/connection/tests/node-half.host.spec.ts \
  packages/client/ui-settings/package.json \
  packages/client/ui-settings/src/client/index.ts \
  packages/client/ui-settings/src/client/settings-scope.ts \
  packages/client/ui-settings/tests/plugin.client.spec.ts \
  packages/client/ui-settings/tests/settings-scope.client.spec.ts \
  packages/host/apiproxy/src/index.ts \
  packages/host/apiproxy/src/api-proxy.ts \
  packages/host/apiproxy/tests/api-proxy-config.spec.ts \
  packages/host/apiproxy/tests/session-export.spec.ts \
  pnpm-lock.yaml \
  > patches/public-access.patch
```

Run the command with the patch repository as the current directory, or copy the generated file into the repository using a non-destructive transfer.

- [ ] **Step 4: Verify the patch is complete and contains no machine data**

Run:

```bash
grep -n "pinPrivilegedToLoopback\|exposeAllSettingsNamespaces\|allowRemoteSettingsPersistence" \
  patches/public-access.patch
sensitive_re='BEGIN [A-Z ]*PRIVATE KEY|://[^/[:space:]]+:[^/@[:space:]]+@|[A-Za-z]:\\\\Users\\\\|/home/[^/[:space:]]+|/Users/[^/[:space:]]+|/data/deepseek-harness-runtime'
set +e
rg -n "$sensitive_re" patches/public-access.patch
scan_status=$?
set -e
if [[ $scan_status -eq 0 ]]; then
  exit 1
elif [[ $scan_status -ne 1 ]]; then
  exit "$scan_status"
fi
```

Expected: all three config names are found; the sensitive/machine-specific scan prints nothing.

### Task 6: Replace the Repository Layout

**Files:**
- Create: `config/cordis.public-access.yml`
- Create: `scripts/verify.sh`
- Create: `LICENSE`
- Create: `THIRD_PARTY_NOTICES.md`
- Create: `SHA256SUMS` after all other content is final
- Delete: `pinPrivilegedToLoopback.patch`
- Delete: `cordis.yml`
- Delete: `cordis.example.yml`
- Delete: `dsh-start.sh`

- [ ] **Step 1: Create the public access overlay**

Write `config/cordis.public-access.yml`:

```yaml
# Full anonymous remote administration overlay for `dsh web`.
# SECURITY: trustedHosts is not authentication. Protect the public entry with
# real authentication and source restrictions whenever possible.

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

- [ ] **Step 2: Create the read-only verification script**

Write `scripts/verify.sh` as a read-only Bash checker that:

- exits `2` for invalid usage;
- exits `1` unless target HEAD is exactly `47f943859bef60e4160492346772ded9b24f765a`, printing supported and actual hashes;
- requires `sha256sum` and checks patch SHA256 `014e8caddf3219da54bd04aae1c750630c2a9ae600ea6b03b7d72a8c48e8ac4e`; final validation also records stable patch ID `ad3debde77fd08aaf9520e9b620b0d9128d8aeba`;
- parses `diff --git` headers and requires the exact sorted 12-path manifest;
- captures forward and reverse `git apply --check` diagnostics, reports `applicable` or `already-applied` quietly, and prints both diagnostics only if neither direction succeeds;
- verifies each option in its intended source diff section and production settings config forwarding in the client entry;
- parses Cordis `- id:` rows and requires the exact `0.0.0.0` binding and three option values in the correct rows, rejecting missing, duplicate, misplaced, or wrong values;
- prints the complete five-file focused Vitest command and `pnpm run build`.

Set executable permission:

```bash
chmod +x scripts/verify.sh
git add --chmod=+x scripts/verify.sh
```

- [ ] **Step 3: Add an Apache-2.0 license**

Create `LICENSE` using the complete Apache License 2.0 text from:

```text
https://www.apache.org/licenses/LICENSE-2.0.txt
```

The file must start with:

```text
Apache License
Version 2.0, January 2004
http://www.apache.org/licenses/
```

- [ ] **Step 4: Remove the obsolete root files**

Before removing obsolete files, create `THIRD_PARTY_NOTICES.md` with the upstream DeepSeek Harness MIT notice and explain that original patch-kit materials use Apache-2.0 while upstream-derived patch content remains under MIT terms.

Delete:

```text
pinPrivilegedToLoopback.patch
cordis.yml
cordis.example.yml
dsh-start.sh
```

Expected: no compatibility wrappers remain.

### Task 7: Rewrite Documentation

**Files:**
- Modify: `README.md`
- Create: `docs/architecture.md`
- Create: `docs/security.md`
- Create: `docs/troubleshooting.md`
- Create: `docs/version-compatibility.md`
- Create: `docs/validation.md`

- [ ] **Step 1: Rewrite README as the concise entry point**

The README must contain:

```markdown
# DeepSeek Harness Public Access Patch

This repository provides one source patch and one Cordis overlay for explicitly anonymous, trusted-host remote administration of DeepSeek Harness.

> Security warning: anyone who can reach the trusted public authority can use privileged Harness capabilities. `trustedHosts` is not authentication.

## What It Changes

| Control | Safe default | Public overlay |
| --- | --- | --- |
| Privileged RPC loopback pin | enabled | disabled |
| Settings namespace allowlist | enforced | all registered namespaces exposed |
| Remote settings persistence | memory-only | Host-backed |

## Supported Version

DeepSeek Harness commit `47f943859bef60e4160492346772ded9b24f765a`.

## Apply

```bash
git -C /data/deepseek-harness apply --check /path/to/patches/public-access.patch
git -C /data/deepseek-harness apply /path/to/patches/public-access.patch
pnpm --dir /data/deepseek-harness install --frozen-lockfile
pnpm --dir /data/deepseek-harness run build
```

## Run

```bash
dsh web \
  --patch /path/to/config/cordis.public-access.yml \
  --trusted-host harness.example.com \
  --port 7860
```

See `docs/security.md` before exposing the service.
```

Expand the final file with verification commands and links to every document, but do not add installation automation or real deployment identifiers.

- [ ] **Step 2: Write the architecture document**

`docs/architecture.md` must explain these three gates in order:

```text
Browser request
  -> outer Host/Origin/Sec-Fetch-Site trusted-host fence
  -> privileged-method loopback pin
  -> API proxy settings namespace exposure
  -> browser settings Host/memory persistence mode
```

It must also state that the patch does not bypass namespace registration, schema validation, or plugin validators.

- [ ] **Step 3: Write the security document**

`docs/security.md` must state:

- Anonymous callers can read/write exposed settings and credentials.
- Normal Harness tools may provide command execution and file access.
- `trustedHosts` protects request origin matching and DNS rebinding; it does not authenticate users.
- Recommended controls are HTTPS, reverse-proxy authentication, source IP restrictions, a non-root process user, a constrained workspace, and removal of unrelated secrets.
- Wrong Origin must continue to return `403`.

- [ ] **Step 4: Write troubleshooting by symptom**

`docs/troubleshooting.md` must include:

| Symptom | Likely cause |
| --- | --- |
| Public page times out | binding, firewall, port mapping, or proxy issue |
| All API calls return 403 | browser-visible authority missing from `trustedHosts` |
| Only settings/credentials return 403 | privileged loopback option not disabled or old build still running |
| Plugin says namespace not exposed | expose-all option missing, Host plugin not registered, or old Host build |
| Plugin card appears but stays unavailable | remote settings persistence option missing or old client bundle cached |
| Setting save reaches server but is rejected | namespace schema or plugin validator rejected the value |
| Page reconnects continuously | WebSocket upgrade or Host/Origin forwarding issue |

- [ ] **Step 5: Write compatibility and patch refresh instructions**

`docs/version-compatibility.md` must record:

```text
Supported upstream commit: 47f943859bef60e4160492346772ded9b24f765a
```

Refresh workflow:

```bash
git clone https://github.com/deepseek-ai/deepseek-harness.git /tmp/dsh-old
git clone https://github.com/deepseek-ai/deepseek-harness.git /tmp/dsh-new
git -C /tmp/dsh-old checkout 47f943859bef60e4160492346772ded9b24f765a
# Apply the current patch to dsh-old, port the same tested behavior to dsh-new,
# then regenerate public-access.patch from the new supported commit.
```

It must instruct maintainers to run `git apply --check`, all five focused tests, `pnpm run test:gui`, and the full build before changing the supported commit. A nonzero exit always fails. Known optional-architecture, Vite migration/dependency, and chunk-size warnings are acceptable only when the command exits zero; new errors or failures are never ignored.

- [ ] **Step 6: Record final validation evidence**

Create `docs/validation.md` recording HEAD, clean pre-apply status, Node and pnpm versions, patch SHA256 and stable patch ID, exact 12-path manifest, applicable/already-applied exit and stderr counts, install/test/build exit codes and test counts, warning policy, tracked source diff stability, and the fact that ignored/generated build artifacts are expected. Include reproduction commands and state that the evidence is not a cryptographic CI attestation.

### Task 8: Validate the Finished Repository End to End

**Files:**
- Verify: all repository files
- Verify: a second clean DeepSeek Harness checkout

- [ ] **Step 1: Run repository hygiene checks**

Run from the patch repository:

```bash
git diff --check
bash -n scripts/verify.sh
sensitive_re='BEGIN [A-Z ]*PRIVATE KEY|://[^/[:space:]]+:[^/@[:space:]]+@|[A-Za-z]:\\\\Users\\\\|/home/[^/[:space:]]+|/Users/[^/[:space:]]+|/data/deepseek-harness-runtime'
set +e
rg -n --hidden --glob '!.git' --glob '!.git/**' \
  --glob '!docs/superpowers/plans/**' \
  "$sensitive_re" .
scan_status=$?
set -e
if [[ $scan_status -eq 0 ]]; then
  exit 1
elif [[ $scan_status -ne 1 ]]; then
  exit "$scan_status"
fi
```

Expected: all commands exit `0`; the generic credential, private-key, user-home, and machine-runtime scan prints nothing. The plan directory is excluded because it contains the scan expression itself; all other shipped files are scanned.

- [ ] **Step 2: Verify patch applicability on a second clean checkout**

Run:

```bash
git clone https://github.com/deepseek-ai/deepseek-harness.git /data/deepseek-harness-public-access-verification
git -C /data/deepseek-harness-public-access-verification checkout 47f943859bef60e4160492346772ded9b24f765a
scripts/verify.sh /data/deepseek-harness-public-access-verification
```

Expected:

```text
patch state: applicable
```

- [ ] **Step 3: Apply the patch to the verification checkout**

Run:

```bash
git -C /data/deepseek-harness-public-access-verification apply patches/public-access.patch
scripts/verify.sh /data/deepseek-harness-public-access-verification
```

Expected:

```text
patch state: already-applied
```

- [ ] **Step 4: Install dependencies and run focused tests in the verification checkout**

Run:

```bash
export PATH=/data/miniconda/envs/deepseek-harness/bin:$PATH
pnpm --dir /data/deepseek-harness-public-access-verification install --frozen-lockfile
pnpm --dir /data/deepseek-harness-public-access-verification exec vitest run \
  packages/client/connection/tests/node-half.host.spec.ts \
  packages/client/ui-settings/tests/plugin.client.spec.ts \
  packages/client/ui-settings/tests/settings-scope.client.spec.ts \
  packages/host/apiproxy/tests/api-proxy-config.spec.ts \
  packages/host/apiproxy/tests/session-export.spec.ts
```

Expected: all focused tests pass.

- [ ] **Step 5: Run the full build**

Run:

```bash
export PATH=/data/miniconda/envs/deepseek-harness/bin:$PATH
pnpm --dir /data/deepseek-harness-public-access-verification run build
```

Expected: exit code `0`. Known optional-architecture, Vite migration/dependency, and chunk-size warnings may be recorded and accepted only with exit `0`; new errors, test failures, and nonzero exits fail validation. Build-created ignored/generated artifacts are expected, so compare only the tracked source diff for stability.

- [ ] **Step 6: Inspect the final repository diff**

Run:

```bash
git status --short
git diff --stat
git diff -- README.md config docs patches scripts LICENSE THIRD_PARTY_NOTICES.md
```

Expected: only the intended repository restructuring appears in tracked source changes. No commit or push is performed without a separate explicit user request.

- [ ] **Step 7: Generate final content identity**

After every other content edit, generate sorted LF `SHA256SUMS` entries for every final repository file except `SHA256SUMS` itself and `.git` metadata. Run `sha256sum -c SHA256SUMS`. If any file changes afterward, regenerate and recheck the manifest.
