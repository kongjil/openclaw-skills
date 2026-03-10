#!/usr/bin/env python3
import argparse
import json
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Dict, List, Tuple

TARGET_PLAN_ID = 861640
DEFAULT_PATH = Path('/root/projects/网页记录/dataimpulse-localstorage.json')
PLANS_API_URL = 'https://data.dataimpulse.com/api/plans/get_plans'


def load_localstorage(path: Path) -> Dict[str, Any]:
    raw = path.read_text(encoding='utf-8')
    data = json.loads(raw)
    # 有些导出是“JSON 字符串里再包一层 JSON”
    if isinstance(data, str):
        data = json.loads(data)
    return data


def parse_current_user(data: Dict[str, Any]) -> Dict[str, Any]:
    current_user_raw = data.get('currentUser', '{}')
    return json.loads(current_user_raw) if isinstance(current_user_raw, str) else (current_user_raw or {})


def find_plan(plans: List[Dict[str, Any]], plan_id: int) -> Dict[str, Any] | None:
    for p in plans:
        if p.get('plan_id') == plan_id:
            return p
    return None


def fetch_realtime_plans(auth_token: str, timeout: int = 12) -> List[Dict[str, Any]]:
    req = urllib.request.Request(
        PLANS_API_URL,
        method='GET',
        headers={
            'Authorization': f'Bearer {auth_token}',
            'Accept': 'application/json',
        },
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        body = resp.read().decode('utf-8')
    payload = json.loads(body)
    data = payload.get('data', [])
    if not isinstance(data, list):
        raise ValueError('invalid realtime payload: data is not list')
    return data


def get_plan_balance(path: Path, plan_id: int, timeout: int = 12) -> Dict[str, Any]:
    local = load_localstorage(path)
    user_id = str(local.get('userId') or '')
    auth_token = local.get('authToken')

    # 1) 先实时查
    if auth_token:
        try:
            realtime_plans = fetch_realtime_plans(auth_token, timeout=timeout)
            hit = find_plan(realtime_plans, plan_id)
            if hit:
                return {
                    'plan_id': plan_id,
                    'balance_format': hit.get('balance_format'),
                    'balance': hit.get('balance'),
                    'userId': user_id,
                    'source': 'realtime',
                }
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, ValueError, json.JSONDecodeError):
            pass

    # 2) 实时失败时回退 localstorage.currentUser.plans
    current_user = parse_current_user(local)
    plans = current_user.get('plans', []) if isinstance(current_user, dict) else []
    hit = find_plan(plans, plan_id)
    if hit:
        return {
            'plan_id': plan_id,
            'balance_format': hit.get('balance_format'),
            'balance': hit.get('balance'),
            'userId': user_id,
            'source': 'local-fallback',
        }

    raise SystemExit(f'plan_id={plan_id} not found in realtime/local fallback')


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description='DataImpulse 余额检查（实时优先，失败回退 localstorage）')
    parser.add_argument('--path', default=str(DEFAULT_PATH), help='localstorage JSON 路径')
    parser.add_argument('--plan-id', type=int, default=TARGET_PLAN_ID, help='目标 plan_id')
    parser.add_argument('--timeout', type=int, default=12, help='实时查询超时秒数')
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    out = get_plan_balance(Path(args.path), plan_id=args.plan_id, timeout=args.timeout)
    print(json.dumps(out, ensure_ascii=False))


if __name__ == '__main__':
    main()
