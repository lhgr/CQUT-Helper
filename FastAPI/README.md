# 调课通知增强与调课服务

[返回应用主页](../README.md)

“调课通知增强”是 CQUT Helper 的可选功能。应用通过所选服务查询教务系统当前学期的待阅和已阅事项，比较查询结果，并在发现变化时记录通知、刷新受影响的教学周。

不开启此功能不影响登录、普通课表同步、课前提醒或小组件。

## 在应用中使用

### 开启与检查服务

登录并至少打开一次课表后，可从以下位置开启：

- **设置 → 通知与提醒 → 调课通知增强**
- **课表 → 右上角设置 → 调课通知增强**

开启前应用会说明发送的数据用途。确认后，服务地址留空表示使用官方服务；也可以填写自己的服务地址。保存后点击“检查服务可用性”：这会使用当前账号查询当前学期，检查实际查询是否成功，不只是检查网址能否访问。

自定义地址必须是 HTTPS 根地址，不包含接口路径、查询参数或片段，例如：

```text
https://notice.example.com
```

配置自定义地址后，应用只向该地址发送查询，不会在失败时自动切换到官方服务。自建服务应能访问学校统一认证和教务系统。

### 平台与检查时机

| 平台 | 普通课表 | 调课通知增强 |
| --- | --- | --- |
| Android | 前台、手动同步；启用后台刷新后由系统安排后台任务 | 前台、手动检查；启用后台检查后由系统安排后台任务 |
| iPhone | 前台及手动同步 | 启动、返回应用及手动同步时检查，不执行后台调课查询 |

Android 后台检查计划为北京时间 9:00；上午任务失败时计划在 12:00 补跑。0:00—7:00 会跳过后台查询。系统省电策略、后台限制、设备状态和网络都可能影响实际运行时间，计划时间不代表准时执行。

Android 可在**设置 → 同步与修复**查看后台注册状态、最近运行和成功时间。若状态异常，先打开应用检查登录与网络，再重新保存后台设置；也可检查系统的自启动、后台运行和电池优化限制。iPhone 的“同步与修复”可查看同步情况；调课查询在应用启动、返回应用或手动同步时进行。

### 查询结果与提醒

第一次成功查询会保存当前完整结果作为本机基线，不会因历史通知立即逐条提醒。之后应用会比较新旧结果：

- 新增通知：记录变化，并在能够识别受影响周次时刷新相关课表。
- 通知内容变化：更新记录，并刷新受影响的课表周。
- 通知从当前完整查询结果中消失：记录撤销，并刷新之前受影响的周。
- 查询成功但结果为空：作为有效的空结果处理，不表示服务故障。

通知记录保存在本机消息中心。只有成功且标记为完整的结果才用于比较；服务失败或返回不完整数据时不会当作“没有通知”覆盖原有记录。若原文格式不足以识别课程或周次，应用仍可能保留可用记录，但无法准确定位要刷新的课表。

在系统通知权限允许时，应用可发送调课提醒。Android 后台任务及通知时间受系统限制；iPhone 只在应用检查时发现变化后安排提醒，不保证在变化发生时立即查询。

## 数据与服务选择

仅在开启此功能并确认说明后，应用才会把以下信息发送到所选服务：

- 学号
- 教务系统加密密码
- 当前学年学期

加密密码不是明文密码，但仍可用于访问教务系统。本目录的服务实现不会持久化查询凭据；处理请求时会使用凭据登录教务系统。自定义服务的数据处理方式由服务运营者决定。

关闭功能后，应用不会继续访问调课服务；退出登录也会关闭功能并清除已接受的授权状态。清除消息中心只会删除本机的调课历史，不会更改学校系统中的通知。

## 自建调课服务

服务代码位于本目录。

### 运行

需要 Python、pip，以及可安装 `requirements.txt` 的环境。从仓库根目录运行：

```bash
python -m pip install -r FastAPI/requirements.txt
python -m playwright install chromium
python -m uvicorn FastAPI.main:app --host 127.0.0.1 --port 8001 --no-proxy-headers
```

服务先尝试 HTTP 查询，不执行下载的 Node.js 脚本；需要浏览器时使用无头 Chromium 且强制启用 Chromium 沙箱。沙箱启动失败会返回查询失败，不会禁用沙箱重试。服务默认只监听本机回环地址；若要让手机访问，应通过你管理的 HTTPS 入口转发到该端口，并避免记录请求体。应用设置中填写 HTTPS 根地址，不要附加 `/api/jwxt/term-schedule-notices` 路径。

上游地址默认指向学校认证和教务系统。确需覆盖时，可在启动服务的进程环境中设置以下变量；项目不会自动读取 `.env` 文件：

| 环境变量 | 用途 |
| --- | --- |
| `JWXT_CAS_LOGIN_PAGE` | 统一认证登录页地址 |
| `JWXT_CAS_DO_LOGIN` | 统一认证登录提交地址 |
| `JWXT_DBSY_PAGE` | 教务系统待办页面地址 |

可选运行参数包括 `JWXT_PIPELINE_TIMEOUT_SEC`（默认 90 秒，范围 10–300）、`JWXT_RATE_LIMIT_PER_MINUTE`（每 IP 每分钟默认 12 次）和 `JWXT_MAX_CONCURRENT_PIPELINES`（默认 2）。每账号每分钟最多 6 次；同账号、同学期已有查询时返回 409，不创建第二个进程。账号限流只存 SHA-256 摘要，不保存密码；限流身份表各最多 4096 项，满时拒绝新身份直至过期项释放。以上计数与并发上限是单进程的，部署使用一个 Uvicorn worker。

调课请求体上限 20 KiB，其余路径 64 KiB；按流式块计数，读取总预算 10 秒，超限返回 413，读取超时返回 408。

默认只使用 TCP 对端 IP，忽略转发头。代理部署必须保留 `--no-proxy-headers`，并将 `JWXT_TRUSTED_PROXY_CIDRS` 设为实际代理出口 CIDR（例如仅 `127.0.0.1/32`）。应用从 X-Forwarded-For 的右侧逐跳剥除可信代理，首个不可信地址作为客户端；不能把任意左侧值当作客户端。只在 Cloudflare Tunnel 入口不可绕过、代理覆盖并清除用户提交的身份头时，才额外设 `JWXT_TRUST_CF_CONNECTING_IP=true`；这时优先使用受信 TCP 对端提供的 CF-Connecting-IP。不要设置全网 CIDR。

### 公网容器运行

公开查询容器应独立于校历管理容器，不挂载校历数据库、私有源码或管理配置，不传入管理令牌。浏览器和查询工作进程只接收运行所需环境变量白名单，但环境白名单不能替代文件权限与容器隔离。保留旧私有容器的 `/data` 和属主，在新容器运行公开查询服务，无需修改旧数据库权限。

仓库提供 `FastAPI/Dockerfile`，基础镜像为 Python 3.12 / Debian 12；构建时安装现有 `requirements.txt` 和匹配的 Chromium、系统库。镜像仅复制公开查询源码，不包含校历模块或数据库，默认 UID/GID 均为 10001。无需在宿主安装 Node.js。

以下命令在仓库根目录执行。构建需要访问 Python、Debian 和 Playwright 的下载源：

```bash
docker build -f FastAPI/Dockerfile -t cqut-notice:local .
```

本目录已附带 Playwright 官方 seccomp 配置 `FastAPI/seccomp_profile.json`，来源固定于 [ae935a43](https://github.com/microsoft/playwright/blob/ae935a43d9e376e4759548f6b3c6905c7b282333/utils/docker/seccomp_profile.json)。它保留默认拒绝策略，并允许 Chromium 创建沙箱所需的用户命名空间。宿主内核也必须支持非特权用户命名空间，面板须支持非 root 用户、seccomp 和资源上限。

先执行离线浏览器检查。该命令不访问学校，也不会禁用沙箱重试：

```bash
docker run --rm --init --user 10001:10001 \
  --cpus 2 --memory 1536m --pids-limit 256 \
  --read-only --tmpfs /tmp:rw,nosuid,size=512m,mode=1777 \
  --shm-size 256m --security-opt seccomp=./FastAPI/seccomp_profile.json \
  cqut-notice:local python -m FastAPI.check_browser_sandbox
```

检查成功后启动服务：

```bash
docker run -d --name cqut-notice --restart unless-stopped \
  --user 10001:10001 --init --cpus 2 --memory 1536m --pids-limit 256 \
  --read-only --tmpfs /tmp:rw,nosuid,size=512m,mode=1777 \
  --shm-size 256m --security-opt seccomp=./FastAPI/seccomp_profile.json \
  -p 127.0.0.1:8001:8001 cqut-notice:local
```

通过现有 HTTPS 代理将调课路径转发到本机 8001。若已有私有容器占用 8001，可把公开容器映射改成 `127.0.0.1:8002:8001`，并相应调整调课路径的代理目标。不要给公开容器传管理令牌或挂载旧 `/data`。代理等待时间至少 110 秒，覆盖默认查询预算与进程树清理；禁用请求体日志。不添加 `--no-sandbox` 或 privileged。

需要按实际客户端 IP 限流时，将实际代理出口 CIDR 通过 `-e JWXT_TRUSTED_PROXY_CIDRS=...` 注入新容器。Docker 网络下应用看到的 TCP 对端通常是网桥网关或代理容器地址，不一定是 `127.0.0.1`，须按实际网络设置，不要照抄回环示例。

部署前须执行上述离线检查，确认镜像、宿主用户命名空间和 Chromium 沙箱可用。检查失败先修复宿主或面板运行配置，不能关闭 Chromium 沙箱绕过。

### 接口

| 方法与路径 | 用途 |
| --- | --- |
| `GET /health` | 返回服务进程状态。成功响应为 `{"status":"ok","ready":true}`；不检查学校上游是否可用。 |
| `POST /api/jwxt/term-schedule-notices` | 查询当前学期调课通知，供 CQUT Helper 使用。 |

查询接口请求 JSON：

```json
{
  "username": "学号",
  "encrypted_password": "教务系统加密密码",
  "year_term": "2026-2027-1",
  "env": "prod",
  "headless": true
}
```

`username`、`encrypted_password` 和 `year_term` 必填；学期格式为 `YYYY-YYYY-1` 或 `YYYY-YYYY-2`，结束年份须比开始年份大一。保留接收旧客户端的 `env` 和 `headless` 字段，但服务端忽略其值，固定使用服务端上游配置与无头浏览器。

成功响应外层为 `{"success":true,"data":{...}}`。`data` 包含 `year_term`、`generated_at`、`term_schedule_notices_complete`、`term_schedule_notices` 和查询计数等字段。客户端要求 `term_schedule_notices_complete` 为 `true`，且通知列表必须是数组；空数组表示一次完整查询未发现可用调课通知。

失败响应为 `{"success":false,"error":{"code":"...","message":"..."}}`，并使用相应 HTTP 状态码。常见情况包括参数无效（422）、请求过大（413）、请求过频（429）、并发任务已满（503）、学校上游不可用（502）及查询超时（504）。`/health` 成功只说明服务进程在线；要确认当前查询链路可用，请在应用中执行“检查服务可用性”。

## 常见问题

| 提示 | 处理方式 |
| --- | --- |
| `登录凭据缺失` | 重新登录后再检查。 |
| `当前学期信息缺失` | 进入课表并完成同步，确保应用已取得学期信息。 |
| `接口夜间关闭(403)` | 学校上游接口暂时不可用，稍后再试。 |
| `请求过于频繁` / `服务繁忙` | 稍后重试，避免连续点击；自建服务可检查请求频率与并发配置。 |
| `查询超时` / `服务不可用` | 检查网络、服务地址、HTTPS 证书及服务端到学校上游的连接。 |
| `数据完整性未确认` | 更新服务至兼容实现，并确认查询返回完整结果。 |

调课信息用于辅助同步，请以学校官方通知和教务系统安排为准。

## 离线验证

在仓库根目录运行，不访问学校上游：

```bash
python -m unittest FastAPI.test_jwxt_automation FastAPI.test_public_boundaries
```
