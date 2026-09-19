#!/usr/bin/env bash
# ============================================================
# ops-lab 一键部署脚本（在目标服务器上以 root 执行）
# 幂等设计：重复执行安全
# 用法: bash deploy.sh
# ============================================================
set -euo pipefail

PROJECT_DIR="/opt/ops-lab"
LOG_FILE="/var/log/ops-lab-deploy.log"

log() { echo "[$(date '+%F %T')] $*" | tee -a "${LOG_FILE}"; }

cd "${PROJECT_DIR}"

# ---------- 1. 基础系统优化 ----------
log "步骤 1/4: 系统基础配置"

# 无 swap 则加 2G，防止 4G 小内存机器 OOM
if [ "$(swapon --noheadings 2>/dev/null | wc -l)" -eq 0 ]; then
    log "未检测到 swap，创建 2G swapfile..."
    fallocate -l 2G /swapfile && chmod 600 /swapfile \
        && mkswap /swapfile && swapon /swapfile
    grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    log "swap 已启用"
fi

# 内核参数微调
cat > /etc/sysctl.d/99-opslab.conf <<'EOF'
vm.swappiness = 10
vm.overcommit_memory = 1
net.core.somaxconn = 2048
net.ipv4.tcp_syncookies = 1
EOF
sysctl --system >/dev/null

# ---------- 2. 安装 Docker ----------
log "步骤 2/4: 安装 Docker"
if ! command -v docker >/dev/null 2>&1; then
    apt-get update -y
    # Ubuntu 24.04 官方源自带 docker.io + docker-compose-v2，无需外部脚本
    DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io docker-compose-v2
    systemctl enable --now docker
fi
log "Docker 版本: $(docker --version)"
log "Compose 版本: $(docker compose version | head -1)"

# ---------- 3. 配置镜像加速 ----------
log "步骤 3/4: 配置 Docker 镜像加速"
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://docker.1ms.run",
    "https://hub.rat.dev"
  ],
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF
systemctl restart docker
log "镜像加速与日志轮转已配置"

# ---------- 4. 启动整个技术栈 ----------
log "步骤 4/4: 启动 ops-lab 全部服务"
docker compose pull --ignore-buildable-images || log "部分镜像拉取失败，继续尝试构建/启动"
docker compose up -d --build

log "等待服务就绪..."
sleep 10
docker compose ps

# 健康检查：最多等 90 秒
for i in $(seq 1 30); do
    if curl -sf http://127.0.0.1/api/health >/dev/null 2>&1; then
        log "✅ 部署成功！Nginx(80) / Flask / MySQL / Redis / Prometheus / Grafana(3000) 全部就绪"
        exit 0
    fi
    sleep 3
done

log "⚠️ 健康检查未通过，请执行: docker compose -f ${PROJECT_DIR}/docker-compose.yml ps && docker compose logs --tail=50"
exit 1
