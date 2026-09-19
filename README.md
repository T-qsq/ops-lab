# ops-lab — 个人一体化运维监控平台

> 一个跑在 2核4G 云服务器上的迷你生产环境：**Nginx + Flask + MySQL + Redis + Prometheus + Grafana + Shell/Python 自动化**，
> 从零到一完成部署、监控、告警、备份、巡检的完整闭环。

## 一、架构

```
                         ┌──────────────── <你的公网IP> (Ubuntu 24.04, 2C4G) ────────────────┐
  用户/面试官             │                                                                     │
      │ :80              │  ┌──────────┐   反代    ┌──────────────┐      ┌─────────┐           │
      └──────────────────┼─▶│  Nginx   ├──────────▶│ Flask (app)  │─────▶│  Redis  │ 计数缓存   │
                         │  │ :80      │           │  gunicorn×2  │      └─────────┘           │
                         │  └──────────┘           │  /metrics    │      ┌─────────┐           │
                         │                         │  /api/health ├─────▶│  MySQL  │ 业务数据   │
                         │                         └──────┬───────┘      └─────────┘           │
                         │                                │ 抓取 15s                            │
                         │                         ┌──────▼───────┐      ┌──────────────┐      │
                         │   主机指标 :9100        │  Prometheus  │◀─────│ node-exporter│      │
                         │   ┌──────────────┐      │  :9090       │      └──────────────┘      │
                         │   │  Grafana     │◀─────│  + 告警规则   │                            │
                         │   │  :3000 看板  │  查询 └──────────────┘                            │
                         │   └──────────────┘                                                   │
                         │  crontab: 每日备份 MySQL / 每日 Python 巡检                          │
                         └─────────────────────────────────────────────────────────────────────┘
```

## 二、与招聘要求的对照

| 招聘要求 | 本项目体现 |
|---|---|
| 熟悉 Linux 基础操作 | 全程 Ubuntu 24.04 服务器实操：swap、sysctl、crontab、日志 |
| TCP/IP、DNS、HTTP | Nginx 反向代理、gzip、keepalive 连接池、健康检查端点 |
| Docker | 7 个容器全部容器化，compose 编排，资源限制 mem_limit、healthcheck |
| Nginx | 反向代理 upstream + keepalive，access_log 排障 |
| MySQL | 8.0 实例 + utf8mb4 + 连接调优 + mysqldump 每日备份（保留 7 天） |
| Redis | LRU 策略、AOF 持久化，做业务计数与健康探测 |
| Shell / Python 自动化 | `sys_check.sh` 巡检、`backup_mysql.sh` 备份、`system_report.py` 纯标准库巡检 |
| Prometheus / Grafana（加分） | 全套指标采集 + 预置看板 + 5 条告警规则（实例宕机/CPU/内存/磁盘/依赖） |
| 个人服务器实践（加分） | 就部署在你自己的云服务器上，面试可直接远程演示 |

## 三、快速开始

```bash
# 服务器上（Ubuntu 24.04，root）：
git clone https://github.com/T-qsq/ops-lab.git /opt/ops-lab && cd /opt/ops-lab
cp .env.example .env        # 修改密码！
bash deploy.sh              # 一键：系统优化 → 装 Docker → 镜像加速 → 起全部服务
bash scripts/setup_cron.sh  # 注册每日备份与巡检定时任务
```

部署日志：`/var/log/ops-lab-deploy.log`

## 四、部署后访问

| 服务 | 地址 | 说明 |
|---|---|---|
| 应用状态页 | `http://<你的公网IP>/` | Nginx → Flask，Redis 计数 |
| 健康检查 | `http://<你的公网IP>/api/health` | 同时探测 MySQL/Redis |
| Grafana | `http://<你的公网IP>:3000` | admin / 见 .env，已自动导入"服务器总览"看板 |
| Prometheus | 服务器内网 `docker compose exec prometheus wget -qO- localhost:9090/-/healthy` | 出于安全不对外暴露 |

> ⚠️ 记得在云控制台安全组放行 **80、3000**（22 仅对自己 IP 放行更安全）。

## 五、日常运维操作（面试可讲）

```bash
docker compose ps                        # 看容器状态
docker compose logs -f --tail=100 app    # 追应用日志（已限制 10m×3 轮转）
bash scripts/sys_check.sh                # 手动巡检
python3 scripts/system_report.py         # Python 巡检报告（支持 --json）
./scripts/backup_mysql.sh                # 手动备份
tail -5 logs/backup.log                  # 查看备份日志
```

## 六、故障排查思路（排查问题兴趣 ✔）

1. **应用 502**：`docker compose logs app` → 多为 MySQL 未就绪，healthcheck + `restart: unless-stopped` 自动恢复；
2. **磁盘涨满**：Grafana 磁盘面板定位 → `docker system df`、`du -sh /var/lib/docker` → 日志已用 json-file 轮转兜底；
3. **内存告警**：4G 小机器 → swap 2G 兜底 + 每个容器 mem_limit + MySQL buffer_pool 压到 128M；
4. **抓取目标 DOWN**：Prometheus Targets 页 → `docker compose exec prometheus wget -qO- app:5000/metrics` 网络分段排查。

## 七、演进方向（体现学习能力）

- [ ] 接入 Alertmanager → 邮件/企业微信告警
- [ ] 加 Loki 收集容器日志（轻量替代 ELK，适配 4G 内存）
- [ ] 单机 k3s，把 compose 迁移为 Kubernetes Manifests
- [ ] GitHub Actions CI：push 自动构建镜像并部署

## 目录结构

```
ops-lab/
├── docker-compose.yml          # 7 服务编排（含资源限制/健康检查）
├── deploy.sh                   # 一键部署（系统优化→Docker→加速→启动）
├── app/                        # Flask 应用（Redis 计数 + MySQL 探测 + /metrics）
├── nginx/nginx.conf            # 反代配置
├── prometheus/                 # 抓取配置 + 5 条告警规则
├── grafana/                    # 数据源与看板自动 provisioning
└── scripts/
    ├── sys_check.sh            # Shell 巡检
    ├── system_report.py        # Python 巡检（纯标准库，支持 JSON 输出）
    ├── backup_mysql.sh         # 数据库备份（保留 7 天）
    └── setup_cron.sh           # 注册定时任务
```
