#!/usr/bin/env bash
# ============================================================
# MySQL 每日备份脚本
# 用 docker exec 调 mysqldump，gzip 压缩，保留最近 7 份
# 建议由 setup_cron.sh 注册到 crontab，每天凌晨 2 点执行
# ============================================================
set -euo pipefail

BACKUP_DIR="/opt/ops-lab/backups"
KEEP_DAYS=7
CONTAINER="ops-mysql"
STAMP=$(date '+%F_%H%M%S')
FILE="${BACKUP_DIR}/opsdb_${STAMP}.sql.gz"

mkdir -p "${BACKUP_DIR}"

echo "[$(date '+%F %T')] 开始备份 -> ${FILE}"
docker exec "${CONTAINER}" mysqldump -uroot -p"${MYSQL_ROOT_PASSWORD:-root_123456}" \
    --single-transaction --routines --triggers opsdb 2>/dev/null | gzip > "${FILE}"

SIZE=$(du -h "${FILE}" | cut -f1)
if [ "$(stat -c%s "${FILE}")" -lt 1024 ]; then
    echo "[$(date '+%F %T')] 备份文件过小，可能失败！" >&2
    exit 1
fi
echo "[$(date '+%F %T')] 备份完成，大小 ${SIZE}"

# 清理过期备份
find "${BACKUP_DIR}" -name 'opsdb_*.sql.gz' -mtime +${KEEP_DAYS} -delete
echo "[$(date '+%F %T')] 已清理 ${KEEP_DAYS} 天前的旧备份"
