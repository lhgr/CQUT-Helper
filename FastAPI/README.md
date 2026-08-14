# 调课通知服务部署

该服务会在内存中短暂处理学号和教务系统可复用的加密凭证。生产环境必须使用 HTTPS，并将服务部署在受控网络和最小权限账户下。服务代码不会主动持久化请求体，但反向代理、APM 和平台日志也必须关闭请求体记录。

## 必需配置

```text
JWXT_RATE_LIMIT_PER_MINUTE=12
JWXT_MAX_CONCURRENT_PIPELINES=2
JWXT_PIPELINE_TIMEOUT_SEC=90
JWXT_TRUST_PROXY_HEADERS=false
```

- 只有反向代理已经覆盖并清洗 `X-Forwarded-For` 时，才可启用 `JWXT_TRUST_PROXY_HEADERS`。
- 服务不再校验移动客户端内置的共享 API Key。该 Key 可从客户端提取，不能作为可靠的用户身份凭证。
- 公网部署仍应在反向代理或 API 网关设置 IP 限流、请求体大小限制、连接超时与必要的访问控制；应用内仍保留按来源地址限流、并发限制和请求体大小限制。

## 启动示例

安装 Python 依赖和 Playwright Chromium，并确保主机具有 Node.js：

```shell
pip install -r requirements.txt
playwright install --with-deps chromium
uvicorn jwxt_automation:app --host 127.0.0.1 --port 8000 --workers 1
```

建议由 Caddy、Nginx 或云 API 网关终止 TLS。应用内限流按进程保存，因此使用多个 Uvicorn worker 或多实例部署时，必须把全局限流放到网关或 Redis 等共享设施中。

健康检查 `GET /health` 只反映进程存活状态。客户端的“检查服务可用性”会实际调用调课接口并校验能否获取当前学期的调课信息。调课接口错误统一为：

成功响应中的 `data.term_schedule_notices_complete` 固定为 `true`，表示 `term_schedule_notices` 是完整结果。客户端只有在该标记存在且列表格式正确时，才会接受空列表并处理调课通知撤销。

```json
{
  "success": false,
  "error": {
    "code": "rate_limited",
    "message": "请求过于频繁，请稍后再试"
  }
}
```
