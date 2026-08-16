# DeepSeek Harness Public Access Patch Refactor

## Purpose

Refactor this repository into a focused patch kit that removes every DeepSeek Harness restriction preventing a declared trusted host from using the complete Web UI over a non-loopback address.

The repository remains a patch project. It does not install DeepSeek Harness, Node.js, pnpm, reverse proxies, authentication, or operating-system services.

## Problem

DeepSeek Harness has three independent controls that affect a public Web UI deployment:

1. The connection package applies a second loopback-only trust check to privileged RPC methods even after a request passes the outer `trustedHosts` check.
2. The Host API proxy exposes only an explicit set of settings namespaces to configuration clients. Third-party plugin namespaces are hidden even when their Host plugins register valid settings schemas.
3. The browser settings binder forces non-loopback pages into process-local memory mode, so settings cards cannot read or persist Host settings even when the Host API permits those calls.

Changing only one control produces partial behavior. For example, settings RPCs may return HTTP 200 while third-party cards still report that their namespace is unavailable.

## Scope

The refactor will provide one source patch and one Cordis patch overlay that address all three controls.

Included:

- Bind the Web server to `0.0.0.0` through the Cordis overlay.
- Make the privileged RPC loopback pin configurable.
- Make all registered settings namespaces exposable through one configuration switch.
- Make Host-backed settings persistence available to trusted remote pages through one configuration switch.
- Preserve safe upstream defaults when the overlay is not applied.
- Provide focused architecture, security, compatibility, troubleshooting, and verification documentation.
- Provide a verification script that checks patch applicability and the expected source changes.

Excluded:

- Automatic DeepSeek Harness installation or dependency management.
- Service managers, containers, reverse proxies, TLS, or authentication.
- Maintaining compatibility entry points for the repository's old root-level files.
- Exposing a settings namespace that its Host plugin never registered.
- Bypassing settings schemas, validators, credential rules, or the outer request trust fence.

## Repository Structure

```text
deepseek-harness-deployment-plug/
├── README.md
├── LICENSE
├── THIRD_PARTY_NOTICES.md
├── SHA256SUMS
├── config/
│   └── cordis.public-access.yml
├── docs/
│   ├── architecture.md
│   ├── security.md
│   ├── troubleshooting.md
│   ├── validation.md
│   ├── version-compatibility.md
│   └── superpowers/specs/2026-08-16-public-access-patch-refactor-design.md
├── patches/
│   └── public-access.patch
└── scripts/
    └── verify.sh
```

The old root-level `cordis.yml`, `cordis.example.yml`, `dsh-start.sh`, and `pinPrivilegedToLoopback.patch` will be removed rather than retained as compatibility wrappers.

## Approved Upstream Patch File Map

The combined patch contains these 12 upstream files:

- `packages/client/connection/src/index.ts`
- `packages/client/connection/tests/node-half.host.spec.ts`
- `packages/client/ui-settings/package.json`
- `packages/client/ui-settings/src/client/index.ts`
- `packages/client/ui-settings/src/client/settings-scope.ts`
- `packages/client/ui-settings/tests/plugin.client.spec.ts`
- `packages/client/ui-settings/tests/settings-scope.client.spec.ts`
- `packages/host/apiproxy/src/api-proxy.ts`
- `packages/host/apiproxy/src/index.ts`
- `packages/host/apiproxy/tests/api-proxy-config.spec.ts`
- `packages/host/apiproxy/tests/session-export.spec.ts`
- `pnpm-lock.yaml`

The client plugin entry is required to forward the production Cordis configuration into `SettingsScopeBinder`. The client package manifest and lockfile make Schemastery a runtime dependency for the exported plugin schema. The production plugin integration test proves configuration forwarding, while the API proxy session-export assertions ensure the new schema default composes with existing defaults. These files are part of the approved behavior, not incidental generated changes.

## Patch Design

### Privileged RPC Access

Target package: `packages/client/connection`

Add `pinPrivilegedToLoopback?: boolean` to `ConnectionConfig` and its schema.

- Default: `true`.
- `true`: preserve upstream behavior. Privileged methods must pass an additional trust check with an empty trusted-host list, which pins them to loopback.
- `false`: skip only the additional privileged-method check. The outer Host, Origin, Fetch Metadata, and `trustedHosts` checks remain active.

The privileged method list is not changed.

### Settings Namespace Exposure

Target package: `packages/host/apiproxy`

Add `exposeAllSettingsNamespaces?: boolean` to the API proxy plugin configuration and pass it into `createApiProxy` defaults.

- Default: `false`.
- `false`: preserve the current provider, Web, and product namespace allowlists.
- `true`: expose every namespace returned by the composed Host settings provider.

The switch changes which already-registered descriptors pass the API proxy filter. It does not create namespaces, accept arbitrary unregistered names, bypass settings schema validation, or bypass write rejection in the settings provider.

When expose-all is true, the implementation may bypass the allowlist filter for descriptions and the allowlist write gate. The default path must continue through `exposedNamespaces()`. It must not hard-code third-party package names such as `pet` or `describe-image`.

### Remote Settings Persistence

Target package: `packages/client/ui-settings`

Add `allowRemoteSettingsPersistence?: boolean` to the settings binder plugin configuration.

- Default: `false`.
- `false`: preserve the current behavior in which non-loopback pages use memory mode.
- `true`: use Host mode for both loopback and remote pages.

Host mode still relies on `settings.describe` and `settings.mutate`. If the request trust fence or namespace exposure rejects the operation, existing unavailable/recovery behavior remains responsible for the client state.

## Cordis Overlay

`config/cordis.public-access.yml` will explicitly opt into all public-access behavior:

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

The Cordis row IDs above match DeepSeek Harness commit `47f943859bef60e4160492346772ded9b24f765a`, where `api-gateway` mounts `@deepseek-ai/dsh-host-apiproxy` and `ui-settings` mounts `@deepseek-ai/dsh-client-ui-settings`.

## User Workflow

The primary workflow will be:

```bash
git clone https://github.com/deepseek-ai/deepseek-harness.git /data/deepseek-harness
git -C /data/deepseek-harness apply --check /path/to/patches/public-access.patch
git -C /data/deepseek-harness apply /path/to/patches/public-access.patch
pnpm --dir /data/deepseek-harness install --frozen-lockfile
pnpm --dir /data/deepseek-harness run build
dsh web \
  --patch /path/to/config/cordis.public-access.yml \
  --trusted-host PUBLIC_AUTHORITY \
  --port 7860
```

`PUBLIC_AUTHORITY` is the browser-visible hostname or `host:port`, without a scheme or path.

## Verification

### Patch Verification Script

`scripts/verify.sh` will accept a DeepSeek Harness checkout path and:

1. Require HEAD to equal `47f943859bef60e4160492346772ded9b24f765a`; any other commit is an exit-1 failure with exact supported and actual hashes.
2. Require `sha256sum` and verify patch SHA256 `014e8caddf3219da54bd04aae1c750630c2a9ae600ea6b03b7d72a8c48e8ac4e`; validation records stable patch ID `ad3debde77fd08aaf9520e9b620b0d9128d8aeba`.
3. Parse `diff --git` headers and require the exact sorted 12-path manifest with no missing or extra paths.
4. Run quiet forward and reverse `git apply --check` probes, report `applicable` or `already-applied`, and print both captured diagnostics only if neither probe succeeds.
5. Verify `pinPrivilegedToLoopback` appears in the `packages/client/connection/src/index.ts` diff section.
6. Verify `exposeAllSettingsNamespaces` appears in the `packages/host/apiproxy/src/index.ts` or `packages/host/apiproxy/src/api-proxy.ts` diff section.
7. Verify `allowRemoteSettingsPersistence` appears in the settings-scope diff and the production client entry forwards `SettingsScopeBinderConfig` into `SettingsScopeBinder`.
8. Require exact overlay row/value pairs for `0.0.0.0` binding and all three public-access options; reject wrong rows, values, duplicates, missing rows, or extra occurrences of those keys.
9. Print the complete five-file focused test command and build command.

The script will not modify the target checkout.

Validation records HEAD, clean pre-apply status, patch SHA256, stable patch ID, exact manifest, both patch states, tool versions, exit codes and test counts. Build output may create ignored/generated artifacts; stability claims apply only to the tracked source diff. `SHA256SUMS` supplies complete final kit content identity and must be regenerated after any repository content edit.

### Upstream Tests

The patch will extend existing upstream tests and default-schema integration assertions:

- Connection tests prove a declared trusted authority can reach privileged methods when the pin is disabled and an undeclared authority still receives `403`.
- API proxy configuration tests prove `exposeAllSettingsNamespaces: true` includes a registered third-party namespace while an unregistered namespace remains rejected.
- Settings scope tests prove a non-loopback browser uses Host mode when `allowRemoteSettingsPersistence` is enabled and preserves memory mode when it is disabled.
- Client plugin integration tests prove the production plugin entry forwards `allowRemoteSettingsPersistence` into the binder.
- API proxy session-export tests prove the new `exposeAllSettingsNamespaces: false` schema default composes with existing gateway defaults.

### Runtime Smoke Tests

The documentation will include checks for:

- Public page returns `200`.
- Correct Origin can call `settings.describe`.
- Wrong Origin returns `403`.
- `settings.describe` includes a registered third-party namespace.
- A third-party settings card can save and reload a value.
- `/api/events.mux` and `/api/events.host` WebSockets connect through the public entry.

## Error Handling

- Patch drift: `git apply --check` fails before any source changes are made. The compatibility document records the supported upstream commit and how to collect a new patch.
- Missing Host namespace: the API proxy cannot expose a namespace absent from `settings.describe`; troubleshooting will distinguish registration failures from exposure failures.
- Remote API rejection: the client remains unavailable or recovers through its existing settings scope behavior. The patch does not hide HTTP or business-layer errors.
- Incorrect trusted host: requests continue to return `403`; documentation will emphasize browser-visible authority and Origin matching.
- Invalid plugin settings: existing namespace schema and plugin validators continue to reject the write.

## Security Model

All new options retain safe defaults and require the public overlay to opt in.

Applying the overlay creates an anonymous remote administration surface. Anyone who can reach a trusted public authority may read or write exposed settings, manage credentials, access privileged Host actions, and potentially execute commands through normal Harness capabilities.

`trustedHosts` is not authentication. It is a request-origin and DNS-rebinding protection boundary. Recommended mitigations are reverse-proxy authentication, source IP restrictions, HTTPS, a non-root process user, a constrained workspace, and removal of unrelated credentials and private keys from the runtime environment.

## Compatibility Policy

The first refactored release will target one documented DeepSeek Harness commit. The patch header and compatibility document will record that commit.

The repository will not initially maintain parallel patches for multiple upstream versions. When upstream changes break `git apply --check`, the patch will be regenerated and the supported commit updated.

## Success Criteria

- A fresh supported DeepSeek Harness checkout accepts `patches/public-access.patch` with `git apply --check`.
- All three configuration switches default to the upstream-safe behavior.
- The supplied overlay enables complete remote settings and privileged functionality for declared trusted hosts.
- Registered third-party settings namespaces become visible without naming individual plugins in this repository.
- Untrusted Host or Origin requests remain rejected.
- Existing schema and plugin validation remain active.
- Focused upstream tests and the full build pass on the supported checkout.
- The five focused files, GUI suite, and build exit zero; only documented optional-architecture, Vite migration/dependency, and chunk-size warnings are accepted when the command succeeds.
- The tracked source diff remains stable across build validation; ignored/generated artifacts are expected and are not claimed immutable.
- The repository contains no real domain, IP address, password, key, or machine-specific runtime path beyond documented examples.
