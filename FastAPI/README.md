# 调课通知服务部署

该服务会在内存中短暂处理学号和教务系统可复用的加密凭证。生产环境必须使用 HTTPS，并将服务部署在受控网络和最小权限账户下。服务代码不会主动持久化请求体，但反向代理、APM 和平台日志也必须关闭请求体记录。

## 必需配置

```text
JWXT_REQUIRE_API_KEY=true
JWXT_API_KEYS=<至少 32 字节的随机令牌>
JWXT_RATE_LIMIT_PER_MINUTE=12
JWXT_MAX_CONCURRENT_PIPELINES=2
JWXT_PIPELINE_TIMEOUT_SEC=90
JWXT_TRUST_PROXY_HEADERS=false
```

- `JWXT_API_KEYS` 支持逗号分隔的多个令牌，便于无停机轮换。
- 只有反向代理已经覆盖并清洗 `X-Forwarded-For` 时，才可启用 `JWXT_TRUST_PROXY_HEADERS`。
- 移动客户端中的共享 API Key 只能降低匿名滥用，不能视为不可提取的用户身份凭证。公网部署仍应在反向代理或 API 网关设置 IP 限流、请求体大小限制和连接超时。
- 应用 Release 构建通过 `--dart-define=NOTICE_API_KEY=...` 注入与服务端匹配的令牌。
- 私有局域网、自用部署可显式设置 `JWXT_REQUIRE_API_KEY=false`，不建议公网使用。

## 启动示例

安装 Python 依赖和 Playwright Chromium，并确保主机具有 Node.js：

```shell
pip install -r requirements.txt
playwright install --with-deps chromium
uvicorn jwxt_automation:app --host 127.0.0.1 --port 8000 --workers 1
```

建议由 Caddy、Nginx 或云 API 网关终止 TLS。应用内限流按进程保存，因此使用多个 Uvicorn worker 或多实例部署时，必须把全局限流放到网关或 Redis 等共享设施中。

健康检查 `GET /health` 不接收凭证，会返回服务是否完成鉴权配置。调课接口错误统一为：

```json
{
  "success": false,
  "error": {
    "code": "rate_limited",
    "message": "请求过于频繁，请稍后再试"
  }
}
```

