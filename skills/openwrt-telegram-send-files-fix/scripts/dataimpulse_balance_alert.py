#!/usr/bin/env python3
import argparse
from pathlib import Path

from dataimpulse_balance_check import DEFAULT_PATH, TARGET_PLAN_ID, get_plan_balance


BYTES_PER_GB = 1024 ** 3


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description='DataImpulse 余额阈值提醒')
    parser.add_argument('--path', default=str(DEFAULT_PATH), help='localstorage JSON 路径')
    parser.add_argument('--plan-id', type=int, default=TARGET_PLAN_ID, help='目标 plan_id')
    parser.add_argument('--timeout', type=int, default=12, help='实时查询超时秒数')
    parser.add_argument('--lt-gb', type=float, required=True, help='低于该阈值(GB)触发提醒并返回非0')
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    info = get_plan_balance(Path(args.path), plan_id=args.plan_id, timeout=args.timeout)

    balance_raw = info.get('balance')
    try:
        balance_bytes = float(balance_raw)
    except (TypeError, ValueError):
        print(
            f"[WARN] 无法解析 balance 数值: {balance_raw!r} | "
            f"plan_id={info.get('plan_id')} userId={info.get('userId')} source={info.get('source')}"
        )
        raise SystemExit(2)

    balance_gb = balance_bytes / BYTES_PER_GB
    threshold = float(args.lt_gb)

    if balance_gb < threshold:
        print(
            f"[ALERT] DataImpulse 余额低于阈值: {balance_gb:.2f} GB < {threshold:.2f} GB | "
            f"plan_id={info.get('plan_id')} userId={info.get('userId')} "
            f"balance_format={info.get('balance_format')} source={info.get('source')}"
        )
        raise SystemExit(1)

    print(
        f"[OK] DataImpulse 余额充足: {balance_gb:.2f} GB >= {threshold:.2f} GB | "
        f"plan_id={info.get('plan_id')} userId={info.get('userId')} "
        f"balance_format={info.get('balance_format')} source={info.get('source')}"
    )


if __name__ == '__main__':
    main()
