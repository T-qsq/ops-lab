#!/usr/bin/env python3
"""ops-lab 系统巡检报告 (纯标准库 Python，无需 pip 安装任何依赖)

读取 /proc 生成人类可读的巡检报告，适合 cron 定时跑或面试演示：
    python3 system_report.py
    python3 system_report.py --json     # 输出 JSON，方便接入其他系统
"""
import argparse
import datetime
import json
import os
import re


def read_first(path):
    with open(path) as f:
        return f.read().strip()


def mem_info():
    info = {}
    for line in read_first("/proc/meminfo").splitlines():
        key, val = line.split(":")
        info[key] = int(val.split()[0])  # kB
    total, available = info["MemTotal"], info["MemAvailable"]
    used = total - available
    return {
        "total_gb": round(total / 1024 / 1024, 2),
        "used_gb": round(used / 1024 / 1024, 2),
        "percent": round(used / total * 100, 1),
        "swap_total_mb": info.get("SwapTotal", 0) // 1024,
        "swap_free_mb": info.get("SwapFree", 0) // 1024,
    }


def loadavg():
    l1, l5, l15 = read_first("/proc/loadavg").split()[:3]
    cores = os.cpu_count() or 1
    return {"1min": float(l1), "5min": float(l5), "15min": float(l15),
            "cores": cores, "overloaded": float(l5) > cores}


def disk_usage():
    result = []
    with os.popen("df -P -x tmpfs -x devtmpfs -x overlay") as f:
        next(f)
        for line in f:
            fs, _, _, _, pct, mount = line.split()
            result.append({"fs": fs, "mount": mount, "percent": int(pct.rstrip("%"))})
    return result


def top_processes(n=5):
    procs = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/stat") as f:
                parts = f.read().split()
            name = parts[1].strip("()")
            utime, stime = int(parts[13]), int(parts[14])
            with open(f"/proc/{pid}/statm") as f:
                rss_pages = int(f.read().split()[1])
            procs.append({"pid": int(pid), "name": name,
                          "cpu_ticks": utime + stime,
                          "rss_mb": round(rss_pages * os.sysconf("SC_PAGE_SIZE") / 1024 / 1024, 1)})
        except (OSError, IndexError, ValueError):
            continue
    by_cpu = sorted(procs, key=lambda p: -p["cpu_ticks"])[:n]
    by_mem = sorted(procs, key=lambda p: -p["rss_mb"])[:n]
    return {"top_cpu": by_cpu, "top_mem": by_mem}


def container_count():
    """统计运行中的 docker 容器（无 docker 则返回 None）"""
    cgroup = "/sys/fs/cgroup"
    try:
        if os.path.isdir(f"{cgroup}/system.slice/docker"):
            return len(os.listdir(f"{cgroup}/system.slice/docker"))
        with open(f"{cgroup}/cgroup.procs") as f:
            return None  # cgroup v2 结构不同，简单跳过
    except OSError:
        return None


def report():
    return {
        "timestamp": datetime.datetime.now().isoformat(timespec="seconds"),
        "hostname": read_first("/proc/sys/kernel/hostname"),
        "kernel": os.uname().release,
        "uptime_hours": round(int(read_first("/proc/uptime").split()[0]) / 3600, 1),
        "load": loadavg(),
        "memory": mem_info(),
        "disks": disk_usage(),
        "processes": top_processes(),
        "docker_running": container_count(),
    }


def human(r):
    lines = [
        f"===== ops-lab Python 巡检报告  {r['timestamp']} =====",
        f"主机: {r['hostname']}  内核: {r['kernel']}  已运行 {r['uptime_hours']}h",
        "",
        f"负载: {r['load']['1min']} / {r['load']['5min']} / {r['load']['15min']} "
        f"({r['load']['cores']} 核)" + ("  [警告: 过载]" if r['load']['overloaded'] else ""),
        f"内存: {r['memory']['used_gb']}G / {r['memory']['total_gb']}G ({r['memory']['percent']}%)"
        f"  Swap 剩余 {r['memory']['swap_free_mb']}MB",
        "",
        "磁盘:",
    ]
    for d in r["disks"]:
        mark = "  << 警告" if d["percent"] > 85 else ""
        lines.append(f"  {d['mount']:<20} {d['percent']}%{mark}")
    lines += ["", "CPU 累计 TOP5:"]
    for p in r["processes"]["top_cpu"]:
        lines.append(f"  {p['pid']:>7}  {p['name']:<20} ticks={p['cpu_ticks']}")
    lines.append("内存 TOP5:")
    for p in r["processes"]["top_mem"]:
        lines.append(f"  {p['pid']:>7}  {p['name']:<20} rss={p['rss_mb']}MB")
    if r["docker_running"] is not None:
        lines.append(f"\n运行中的容器: {r['docker_running']}")
    return "\n".join(lines)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true", help="输出 JSON 格式")
    args = ap.parse_args()
    r = report()
    print(json.dumps(r, ensure_ascii=False, indent=2) if args.json else human(r))
