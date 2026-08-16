# 架构

本补丁把匿名远程 Web UI 所需的行为拆成三个独立、默认关闭的配置开关。请求与设置数据按以下四步流动：

```text
浏览器请求
  -> 外层 Host / Origin / Sec-Fetch-Site 可信请求栅栏
  -> 条件式特权方法回环限制
  -> API 代理设置命名空间暴露
  -> 客户端 Host / memory 设置模式
```

## 1. 外层可信请求栅栏

`connection.trustedHosts` 声明浏览器实际访问的 authority。所有 API 请求和 WebSocket upgrade 仍先检查 Host、Origin 与 Fetch Metadata，用于拒绝未声明 authority、跨站请求和 DNS rebinding。补丁没有增加绕过该层的选项。

## 2. 特权方法回环限制

`connection.pinPrivilegedToLoopback` 默认是 `true`。

- `true`：请求通过外层栅栏后，设置、凭据、宿主文件操作、模型发现和 Agent 预设等特权 RPC 仍需通过空可信列表检查，因此只允许回环来源。
- `false`：跳过这一次附加回环检查，让已通过外层栅栏的声明 authority 调用特权 RPC。

该选项不修改特权方法集合，也不关闭 Host、Origin、`Sec-Fetch-Site` 或 `trustedHosts` 检查。

## 3. 设置命名空间暴露

`api-gateway.exposeAllSettingsNamespaces` 默认是 `false`。

- `false`：API 代理继续只返回并写入既有 allowlist 中的 provider、Web 和产品设置命名空间。
- `true`：`settings.describe` 返回组合 Host settings provider 已注册的全部命名空间，设置写入也不再被代理 allowlist 提前拒绝。

此开关只改变 API 代理的暴露过滤。它不会注册新命名空间，不接受不存在的命名空间，不绕过命名空间 schema、settings provider 校验或插件 validator。未注册名称仍由 provider 以 `settings-rejected` 拒绝。

## 4. 客户端设置持久化模式

`ui-settings.allowRemoteSettingsPersistence` 默认是 `false`。

- `false`：非回环页面使用 `memory` 模式，不调用 Host 设置接口，页面刷新后本地值不会作为 Host 配置保留。
- `true`：非回环页面和回环页面都使用 `host` 模式，通过 `settings.describe`、刷新和 mutate 流程读取与保存设置。

Host 模式仍依赖前三层允许请求并暴露对应命名空间。HTTP 拒绝、缺失命名空间、schema 错误和插件业务校验仍按上游行为呈现为不可用或写入失败。

## 覆盖层组合

`config/cordis.public-access.yml` 将 Web server 绑定到全部接口，并同时开启三个选项。缺少任一选项都会形成不完整行为，例如特权 RPC 已可达但第三方设置卡仍不可用。所有源码配置默认值保持安全，因此不应用覆盖层时，上游行为不变。

## 版本绑定

该数据流只在支持的上游 commit `47f943859bef60e4160492346772ded9b24f765a` 上完成验证。验证器对其他 HEAD 直接退出 `1`，即使 Git hunk 暂时仍能匹配也不代表架构语义未漂移；必须按版本兼容流程移植三层控制、重新生成补丁并完成五个聚焦测试、GUI 测试和完整构建。
