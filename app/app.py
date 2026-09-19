"""ops-lab 核心业务应用
Flask API：Redis 计数 / MySQL 健康检查 / Prometheus 指标暴露
"""
import os
import socket
import time

import pymysql
import redis
from flask import Flask, jsonify
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, generate_latest

app = Flask(__name__)

REDIS_HOST = os.getenv("REDIS_HOST", "redis")
MYSQL_CONF = dict(
    host=os.getenv("MYSQL_HOST", "mysql"),
    port=3306,
    user=os.getenv("MYSQL_USER", "ops"),
    password=os.getenv("MYSQL_PASSWORD", "ops_123456"),
    database=os.getenv("MYSQL_DATABASE", "opsdb"),
    connect_timeout=3,
)

rdb = redis.Redis(host=REDIS_HOST, port=6379, decode_responses=True)

VISIT_TOTAL = Counter("app_visits_total", "HTTP visit counter (redis backed)")
MYSQL_UP = Gauge("app_mysql_up", "MySQL connectivity, 1=ok 0=down")
REDIS_UP = Gauge("app_redis_up", "Redis connectivity, 1=ok 0=down")
START_TIME = time.time()


def check_mysql() -> bool:
    try:
        conn = pymysql.connect(**MYSQL_CONF)
        with conn.cursor() as cur:
            cur.execute("SELECT 1")
            cur.fetchone()
        conn.close()
        return True
    except Exception:
        return False


def check_redis() -> bool:
    try:
        rdb.ping()
        return True
    except Exception:
        return False


@app.get("/")
def index():
    """简单状态页，Nginx 反代到这里"""
    visits = 0
    try:
        visits = rdb.incr("ops:visits")
        VISIT_TOTAL.inc()
    except Exception:
        pass
    return f"""<!doctype html>
<html lang="zh"><head><meta charset="utf-8">
<title>ops-lab</title>
<style>
 body{{font-family:system-ui,'Segoe UI',sans-serif;background:#0f172a;color:#e2e8f0;
      display:flex;align-items:center;justify-content:center;height:100vh;margin:0}}
 .card{{background:#1e293b;padding:40px 56px;border-radius:16px;box-shadow:0 8px 30px rgba(0,0,0,.4)}}
 h1{{margin:0 0 8px;font-size:28px}} .ok{{color:#4ade80}} code{{color:#93c5fd}}
 p{{color:#94a3b8;margin:6px 0}}
</style></head>
<body><div class="card">
 <h1>🚀 ops-lab 运行中 <span class="ok">●</span></h1>
 <p>主机名: <code>{socket.gethostname()}</code></p>
 <p>访问次数 (Redis 计数): <code>{visits}</code></p>
 <p>接口: <code>/api/health</code> · <code>/api/visit</code> · <code>/metrics</code></p>
 <p>Grafana: <code>:3000</code> | Prometheus: <code>prometheus:9090</code></p>
</div></body></html>"""


@app.get("/api/health")
def health():
    mysql_ok, redis_ok = check_mysql(), check_redis()
    MYSQL_UP.set(1 if mysql_ok else 0)
    REDIS_UP.set(1 if redis_ok else 0)
    code = 200 if (mysql_ok and redis_ok) else 503
    return jsonify(
        status="ok" if (mysql_ok and redis_ok) else "degraded",
        mysql=mysql_ok,
        redis=redis_ok,
        uptime_seconds=round(time.time() - START_TIME, 1),
    ), code


@app.get("/api/visit")
def visit():
    VISIT_TOTAL.inc()
    return jsonify(visits=rdb.incr("ops:visits"))


@app.get("/metrics")
def metrics():
    MYSQL_UP.set(1 if check_mysql() else 0)
    REDIS_UP.set(1 if check_redis() else 0)
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
