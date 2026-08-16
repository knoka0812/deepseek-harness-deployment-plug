# 安全

## 威胁模型

应用公共访问覆盖层后，DeepSeek Harness 成为匿名远程管理面。任何能够访问已声明可信 authority 的调用者都可能：

- 读取和修改所有已暴露设置，包括已注册的第三方命名空间。
- 查询、设置或删除 Harness 管理的凭据。
- 调用宿主路径、Agent 预设和模型发现等特权接口。
- 使用 Harness 正常提供的工具访问工作区文件或执行命令。
- 观察可用于进一步探测运行环境的配置与能力信息。

因此，网络可达性本身必须被视为管理权限授予。

## `trustedHosts` 不是认证

`trustedHosts` 校验浏览器可见 authority，并与 Host、Origin、`Sec-Fetch-Site` 检查共同抵御跨站请求和 DNS rebinding。它不验证用户身份，不区分多个访问者，也不提供权限、会话或审计机制。知道地址且能够连通服务的人仍是匿名调用者。

## 保留的安全边界

补丁和覆盖层不会移除以下边界：

- 未声明 Host、错误 Origin 和不可信 Fetch Metadata 仍被外层请求栅栏拒绝。
- WebSocket upgrade 仍经过同一可信请求判断。
- 只有 Host settings provider 已注册的命名空间能够被描述或写入。
- 命名空间 schema、settings provider 校验和插件 validator 仍会拒绝无效值。
- 凭据域自身的规则、路径处理和各工具的既有检查保持不变。

这些边界不能替代身份认证。

验证器只接受精确支持 commit。对其他 commit 放宽为警告会让请求栅栏、凭据接口或设置 validator 的上游语义漂移被误判为安全，因此 commit 不匹配是退出码 `1` 的硬失败，必须移植并重新验证。

## 缓解措施

- 使用 HTTPS，避免管理流量和凭据在传输中暴露。
- 在反向代理实施强身份认证，不要直接公开匿名入口。
- 使用防火墙、网络 ACL 或代理 allowlist 限制来源 IP。
- 以非 root、最小权限用户运行 Harness。
- 将工作目录限制在专用、受控的 workspace。
- 从进程环境、配置目录和 workspace 移除与 Harness 无关的密码、令牌、私钥及其他秘密。
- 确认反向代理正确转发 Host、Origin 和 WebSocket upgrade，而不是放宽应用检查。

## 错误 Origin 冒烟测试

启动后必须确认错误 Origin 仍返回 `403`：

```bash
PUBLIC_URL='https://PUBLIC_AUTHORITY'

curl -sS -o /dev/null -w '%{http_code}\n' -X POST \
  -H 'Content-Type: application/json' \
  -H 'Origin: https://wrong-origin.invalid' \
  -H 'Sec-Fetch-Site: cross-site' \
  --data '{"type":"client-request","rpcId":"security-smoke","method":"settings.describe","payload":{}}' \
  "$PUBLIC_URL/api/settings.describe"
```

预期输出为 `403`。若返回 `200`，停止公开服务并检查代理是否重写了 Host、Origin 或 Fetch Metadata。
