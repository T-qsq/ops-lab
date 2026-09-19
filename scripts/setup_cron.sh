#!/usr/bin/env bash
# ============================================================
# 注册定时任务：数据库备份(每天 02:00) + 系统巡检(每天 09:00)
# 幂等：重复执行不会产生重复条目
# ============================================================
set -euo pipefail

PROJECT_DIR="/opt/ops-lab"
MARK="# ops-lab-managed"

CRON_LINE=(
  "0 2 * * * ${PROJECT_DIR}/scripts/backup_mysql.sh >> ${PROJECT_DIR}/logs/backup.log 2>&1 ${MARK}"
  "0 9 * * * /usr/bin/python3 ${PROJECT_DIR}/scripts/system_report.py >> ${PROJECT_DIR}/logs/inspection.log 2>&1 ${MARK}"
)

mkdir -p "${PROJECT_DIR}/logs"
chmod +x "${PROJECT_DIR}/scripts/"*.sh

EXISTING=$(crontab -l 2>/dev/null || true)
TMP=$(mktemp)
echo "${EXISTING}" > "${TMP}"
for line in "${CRON_LINE[@]}"; do
    if grep -qF "${MARK} $(echo "$line" | awk '{print $NF}')" "${TMP}" 2>/dev/null; then
        continue
    fi
    # 简单幂等：按脚本路径去重
    script=$(echo "$line" | awk '{print $6}')
    if ! grep -qF "$script" "${TMP}"; then
        echo "$line" >> "${TMP}"
        echo "已注册定时任务: $line"
    fi
done
crontab "${TMP}"
rm -f "${TMP}"
echo "当前 crontab:"
crontab -l
