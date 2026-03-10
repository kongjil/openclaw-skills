#!/usr/bin/env python3
import json, sys, os
path = sys.argv[1] if len(sys.argv) > 1 else '/root/.openclaw/workspace/runtime-alerts/openwrt-backup-alert.json'
if not os.path.exists(path):
    print('')
    sys.exit(0)
with open(path, 'r', encoding='utf-8') as f:
    data = json.load(f)
hosts = data.get('hosts') or []
fails = [h for h in hosts if not h.get('ok')]
if not fails:
    print('')
    sys.exit(0)
lines = ['🚨 OpenWrt 备份巡检告警', '', f"时间：{data.get('created_at','')}"]
for h in hosts:
    name = h.get('name','unknown')
    ok = h.get('ok', False)
    reason = h.get('reason','')
    lines.append(f"- {name}：{'正常' if ok else '失败'}" + (f"（{reason}）" if reason and not ok else ''))
lines += ['', '建议检查：']
for h in fails:
    if h.get('log'):
        lines.append(f"- {h['log']}")
    if h.get('dir'):
        lines.append(f"- {h['dir']}")
print('\n'.join(lines))
