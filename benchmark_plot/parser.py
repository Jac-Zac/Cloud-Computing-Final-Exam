import os
import re


def clean(line):
    # Strip ANSI escape sequences
    return re.sub(r"\x1b\[[0-9;]*m", "", line).strip()


def extract_cpu(lines):
    # Extract all "events per second" values from sysbench
    vals = []
    for L in lines:
        if m := re.search(r"events per second:\s*([\d.]+)", L):
            vals.append(float(m.group(1)))
    return sum(vals) / len(vals) if vals else None


def extract_mem(lines):
    # Extract all MiB/sec values from sysbench memory tests
    vals = []
    for L in lines:
        if m := re.search(r"MiB transferred.*\(([\d.]+)\s+MiB/sec\)", L):
            vals.append(float(m.group(1)))
    return sum(vals) / len(vals) if vals else None


def parse_log(path, metric):
    if not os.path.exists(path):
        return None
    with open(path, "r") as f:
        lines = [clean(line) for line in f if line.strip()]
    if metric == "cpu":
        return extract_cpu(lines)
    elif metric == "mem":
        return extract_mem(lines)
    else:
        return None


def parse_logs(log_files):
    """
    log_files: dict of env -> { 'cpu': path, 'mem': path }
    returns: dict of env -> { 'cpu': float|None, 'mem': float|None }
    """
    out = {}
    for env, mets in log_files.items():
        out[env] = {}
        for metric, path in mets.items():
            out[env][metric] = parse_log(path, metric)
    return out
