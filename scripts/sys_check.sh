#!/usr/bin/env bash
# ============================================================
# ops-lab 系统巡检脚本 (Shell)
# 用法: ./sys_check.sh   或 crontab 定时执行并追加到日志
# ============================================================
set -u

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'

echo "=============================================="
echo " ops-lab 巡检报告  $(date '+%F %T')"
echo "=============================================="

# ---- 基本信息 ----
echo -e "\n[主机信息]"
echo "  主机名: $(hostname)"
echo "  内核:   $(uname -r)"
echo "  运行:   $(uptime -p)  (启动于 $(uptime -s))"

# ---- CPU 负载 ----
echo -e "\n[CPU / 负载]"
read -r l1 l5 l15 _ < /proc/loadavg
cores=$(nproc)
echo "  负载: 1分钟=${l1} 5分钟=${l5} 15分钟=${l15} (核心数 ${cores})"
awk -v c="$cores" '{ if ($1/c > 1.0) printf "  '"${RED}"'警告: 负载超过核心数!'"${NC}"'\n" }' /proc/loadavg

# ---- 内存 ----
echo -e "\n[内存]"
free -h | awk 'NR==1 || /Mem|Swap/'

# ---- 磁盘 ----
echo -e "\n[磁盘使用率]"
df -h --output=source,fstype,size,used,avail,pcent,target -x tmpfs -x devtmpfs -x overlay 2>/dev/null || df -h

# ---- TOP 进程 ----
echo -e "\n[CPU TOP5 进程]"
ps -eo pid,comm,%cpu --sort=-%cpu | head -6
echo -e "\n[内存 TOP5 进程]"
ps -eo pid,comm,%mem --sort=-%mem | head -6

# ---- Docker 容器状态 ----
if command -v docker >/dev/null 2>&1; then
    echo -e "\n[Docker 容器]"
    docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null
    abnormal=$(docker ps -a --filter 'status=exited' --filter 'status=dead' -q 2>/dev/null | wc -l)
    if [ "${abnormal}" -gt 0 ]; then
        echo -e "  ${RED}警告: 有 ${abnormal} 个容器状态异常${NC}"
        docker ps -a --filter 'status=exited' --filter 'status=dead' --format '  - {{.Names}} ({{.Status}})'
    else
        echo -e "  ${GREEN}所有容器运行正常${NC}"
    fi
else
    echo -e "\n[Docker] 未安装"
fi

# ---- 安全：登录失败统计 ----
if [ -f /var/log/auth.log ]; then
    fails=$(grep -c 'Failed password' /var/log/auth.log 2>/dev/null || echo 0)
    echo -e "\n[安全] auth.log 中 SSH 登录失败次数: ${fails}"
fi

echo -e "\n=============================================="
echo " 巡检完成"
echo "=============================================="
