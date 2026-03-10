#!/usr/bin/env python3
"""
OpenClaw Deploy Advisor（交互增强版，仍为只读/渲染模式）

目标：
- 检测机器环境 + 网络连通性（best-effort，短超时）
- 输出候选部署方案，支持 A/B/C... 字母映射到 option-id
- 选择某方案后，执行该方案专属依赖缺口分析（不做真实安装）
- 输出状态分级：ready / remediable / unsupported / risky
- 输出补齐计划、部署计划、渲染脚本（仅输出，不执行）

注意：当前版本不会执行 OpenClaw 安装/重启/部署动作。
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import re
import shutil
import socket
import string
import subprocess
import sys
import time
import urllib.error
import urllib.request
from dataclasses import asdict, dataclass
from typing import Any, Dict, List, Optional, Tuple

SCRIPT_VERSION = "0.3.2-apply-confirm-gate"
DEFAULT_TIMEOUT = 2.5
APPLY_PREVIEW_MSG = "当前仅预演，将执行哪些命令；如需真实执行请补充确认参数。"

REMEDIATION_COMMAND_HINTS = {
    "linux-ubuntu": {
        "git": "sudo apt-get install -y git",
        "curl": "sudo apt-get install -y curl",
        "python3": "sudo apt-get install -y python3",
        "node": "sudo apt-get install -y nodejs npm",
        "npm": "sudo apt-get install -y npm",
        "pnpm": "sudo npm install -g pnpm",
        "docker": "sudo apt-get install -y docker.io",
        "podman": "sudo apt-get install -y podman",
        "ssh": "sudo apt-get install -y openssh-client",
        "bun": "curl -fsSL https://bun.sh/install | bash",
    },
    "linux-debian": {
        "git": "sudo apt-get install -y git",
        "curl": "sudo apt-get install -y curl",
        "python3": "sudo apt-get install -y python3",
        "node": "sudo apt-get install -y nodejs npm",
        "npm": "sudo apt-get install -y npm",
        "pnpm": "sudo npm install -g pnpm",
        "docker": "sudo apt-get install -y docker.io",
        "podman": "sudo apt-get install -y podman",
        "ssh": "sudo apt-get install -y openssh-client",
        "bun": "curl -fsSL https://bun.sh/install | bash",
    },
    "linux-wsl2": {
        "git": "sudo apt-get install -y git",
        "curl": "sudo apt-get install -y curl",
        "python3": "sudo apt-get install -y python3",
        "node": "sudo apt-get install -y nodejs npm",
        "npm": "sudo apt-get install -y npm",
        "pnpm": "sudo npm install -g pnpm",
        "docker": "sudo apt-get install -y docker.io",
        "podman": "sudo apt-get install -y podman",
        "ssh": "sudo apt-get install -y openssh-client",
        "bun": "curl -fsSL https://bun.sh/install | bash",
    },
    "macos": {
        "git": "brew install git",
        "curl": "brew install curl",
        "python3": "brew install python3",
        "node": "brew install node",
        "npm": "brew install npm",
        "pnpm": "brew install pnpm",
        "docker": "brew install --cask docker",
        "podman": "brew install podman",
        "ssh": "brew install openssh",
        "bun": "brew install oven-sh/bun/bun",
    },
}


@dataclass
class ToolCheck:
    name: str
    found: bool
    path: Optional[str]
    version: Optional[str]
    note: str = ""


@dataclass
class NetCheck:
    name: str
    url: str
    group: str
    ok: bool
    latency_ms: Optional[int]
    status: str
    detail: str


@dataclass
class DeployOption:
    option_id: str
    title: str
    os_targets: List[str]
    requires: List[str]
    preferred_in: List[str]
    description: str
    risks: List[str]
    steps: List[str]


TOOL_CN_NAME = {
    "docker": "Docker",
    "podman": "Podman",
    "bun": "Bun",
    "node": "Node.js",
    "git": "Git",
    "ssh": "OpenSSH",
    "curl": "curl",
    "python3": "Python3",
    "npm": "npm",
    "pnpm": "pnpm",
    "systemd": "systemd",
}


def run_cmd(cmd: List[str], timeout: float = 2.0) -> Tuple[int, str, str]:
    try:
        cp = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            check=False,
        )
        return cp.returncode, cp.stdout.strip(), cp.stderr.strip()
    except Exception as e:
        return 124, "", str(e)


def detect_os() -> Dict[str, Any]:
    info: Dict[str, Any] = {
        "platform_system": platform.system(),
        "platform_release": platform.release(),
        "platform_version": platform.version(),
        "machine": platform.machine(),
        "python": platform.python_version(),
    }

    os_release = {}
    if os.path.exists("/etc/os-release"):
        try:
            with open("/etc/os-release", "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("#") or "=" not in line:
                        continue
                    k, v = line.split("=", 1)
                    os_release[k] = v.strip().strip('"')
        except Exception:
            pass
    info["os_release"] = os_release

    is_wsl = False
    try:
        with open("/proc/version", "r", encoding="utf-8") as f:
            txt = f.read().lower()
            if "microsoft" in txt or "wsl" in txt:
                is_wsl = True
    except Exception:
        pass
    info["is_wsl"] = is_wsl

    systemd_running = os.path.isdir("/run/systemd/system")
    systemctl_path = shutil.which("systemctl")
    systemd_available = systemctl_path is not None
    info["systemd"] = {
        "running": systemd_running,
        "systemctl": systemctl_path,
        "available": systemd_available,
    }

    return info


def detect_tools(timeout: float = 2.0) -> Dict[str, ToolCheck]:
    checks: Dict[str, ToolCheck] = {}
    version_cmds = {
        "docker": ["docker", "--version"],
        "podman": ["podman", "--version"],
        "bun": ["bun", "--version"],
        "node": ["node", "--version"],
        "git": ["git", "--version"],
        "ssh": ["ssh", "-V"],
        "curl": ["curl", "--version"],
        "python3": ["python3", "--version"],
        "npm": ["npm", "--version"],
        "pnpm": ["pnpm", "--version"],
    }

    for name, cmd in version_cmds.items():
        p = shutil.which(name)
        if not p:
            checks[name] = ToolCheck(name=name, found=False, path=None, version=None)
            continue
        code, out, err = run_cmd(cmd, timeout=timeout)
        ver_src = out or err
        ver_line = ver_src.splitlines()[0] if ver_src else ""
        checks[name] = ToolCheck(
            name=name,
            found=True,
            path=p,
            version=ver_line if code == 0 or ver_line else None,
            note="" if code == 0 else f"exit={code}",
        )

    return checks


def http_probe(url: str, timeout: float = DEFAULT_TIMEOUT) -> Tuple[bool, Optional[int], str, str]:
    req = urllib.request.Request(
        url,
        method="GET",
        headers={"User-Agent": "openclaw-deploy-advisor/0.2"},
    )
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            _ = resp.read(1)
            ms = int((time.time() - t0) * 1000)
            return True, ms, str(resp.status), "ok"
    except urllib.error.HTTPError as e:
        ms = int((time.time() - t0) * 1000)
        code = int(getattr(e, "code", 0) or 0)
        if 400 <= code < 500:
            return True, ms, str(code), f"http-{code}（可达但被拒绝）"
        return False, ms, str(code) if code else "http-error", str(e)[:180]
    except Exception as e:
        ms = int((time.time() - t0) * 1000)
        msg = str(e)
        status = "error"
        m = re.search(r"\b(\d{3})\b", msg)
        if m:
            status = m.group(1)
        return False, ms, status, msg[:180]


def detect_network(timeout: float = DEFAULT_TIMEOUT) -> Dict[str, Any]:
    endpoints = [
        ("npm-registry", "https://registry.npmjs.org/-/ping", "global"),
        ("github", "https://github.com", "global"),
        ("github-api", "https://api.github.com", "global"),
        ("telegram-api", "https://api.telegram.org", "global"),
        ("discord", "https://discord.com/api/v10", "global"),
        ("gitee", "https://gitee.com", "cn"),
        ("npmmirror", "https://registry.npmmirror.com/-/ping", "cn"),
        ("tuna", "https://mirrors.tuna.tsinghua.edu.cn", "cn"),
    ]

    checks: List[NetCheck] = []
    for name, url, grp in endpoints:
        ok, ms, status, detail = http_probe(url, timeout=timeout)
        checks.append(
            NetCheck(
                name=name,
                url=url,
                group=grp,
                ok=ok,
                latency_ms=ms,
                status=status,
                detail=detail,
            )
        )

    ext_ip = None
    ip_ok, _, _, ip_detail = http_probe("https://api.ipify.org?format=json", timeout=timeout)
    if ip_ok:
        try:
            with urllib.request.urlopen("https://api.ipify.org?format=json", timeout=timeout) as r:
                ext_ip = json.loads(r.read().decode("utf-8")).get("ip")
        except Exception:
            pass

    global_total = sum(1 for c in checks if c.group == "global")
    global_ok = sum(1 for c in checks if c.group == "global" and c.ok)
    cn_total = sum(1 for c in checks if c.group == "cn")
    cn_ok = sum(1 for c in checks if c.group == "cn" and c.ok)

    profile, reason = infer_network_profile(checks)

    return {
        "external_ip": ext_ip,
        "external_ip_probe": "ok" if ip_ok else f"failed: {ip_detail}",
        "checks": [asdict(c) for c in checks],
        "summary": {
            "global_ok": global_ok,
            "global_total": global_total,
            "cn_ok": cn_ok,
            "cn_total": cn_total,
        },
        "profile": profile,
        "profile_reason": reason,
    }


def infer_network_profile(checks: List[NetCheck]) -> Tuple[str, str]:
    d = {c.name: c for c in checks}
    global_ok = sum(1 for c in checks if c.group == "global" and c.ok)
    cn_ok = sum(1 for c in checks if c.group == "cn" and c.ok)
    global_total = max(1, sum(1 for c in checks if c.group == "global"))
    cn_total = max(1, sum(1 for c in checks if c.group == "cn"))

    g_ratio = global_ok / global_total
    cn_ratio = cn_ok / cn_total
    tg_ok = d.get("telegram-api").ok if d.get("telegram-api") else False
    discord_ok = d.get("discord").ok if d.get("discord") else False

    if g_ratio >= 0.8 and tg_ok and discord_ok:
        return "global-open-likely", "国际端点高可达，Telegram/Discord 均可达"

    if cn_ratio >= 0.66 and g_ratio <= 0.5 and (not tg_ok or not discord_ok):
        return "cn-restricted-likely", "国内镜像较通畅，部分国际服务受限"

    if g_ratio < 0.4 and cn_ratio < 0.4:
        return "network-degraded", "国内与国际端点均存在较多失败"

    return "mixed-uncertain", "连通性混合，建议按通道逐项验证"


def build_option_catalog() -> List[DeployOption]:
    return [
        DeployOption(
            option_id="ubuntu-systemd-node",
            title="Ubuntu/Debian + Node + systemd 用户服务",
            os_targets=["linux-ubuntu", "linux-debian", "linux-wsl2"],
            requires=["node", "git", "ssh", "curl", "systemd"],
            preferred_in=["global-open-likely", "mixed-uncertain", "cn-restricted-likely"],
            description="官方推荐的稳定路径：Node 运行时 + gateway install + systemd user 托管。",
            risks=[
                "若需公网监听，必须先配置 gateway.auth.token/password",
                "国内网络下需额外验证 Telegram/Discord 可达性与代理",
            ],
            steps=[
                "确认 gateway.mode=local，默认仅监听 loopback",
                "执行 openclaw onboard/configure 完成基础配置",
                "执行 openclaw gateway install 安装用户服务",
                "执行 openclaw gateway status / openclaw logs --follow 验证",
            ],
        ),
        DeployOption(
            option_id="ubuntu-docker-compose",
            title="Ubuntu/Debian + Docker Compose",
            os_targets=["linux-ubuntu", "linux-debian"],
            requires=["docker", "git", "curl"],
            preferred_in=["global-open-likely", "mixed-uncertain"],
            description="容器化部署，便于复制和迁移；注意目录权限与网络策略。",
            risks=[
                "宿主目录权限与 UID/GID 映射不一致可能导致 EACCES",
                "修改 compose 配置后需要重新执行 docker-setup 流程",
            ],
            steps=[
                "准备 Docker 与 Compose 运行环境",
                "执行 docker-setup 生成 compose 配置",
                "完成 onboard 后拉起 openclaw-gateway 容器",
                "检查容器日志与网关健康状态",
            ],
        ),
        DeployOption(
            option_id="ubuntu-podman-rootless",
            title="Ubuntu/Debian + Podman rootless",
            os_targets=["linux-ubuntu", "linux-debian"],
            requires=["podman", "git", "curl"],
            preferred_in=["global-open-likely", "mixed-uncertain"],
            description="rootless 容器方案，适合已有 Podman 经验的环境。",
            risks=[
                "subuid/subgid 或 rootless 用户配置不正确时会失败",
                "运维复杂度通常高于 Node+systemd",
            ],
            steps=[
                "检查 rootless Podman 与 subuid/subgid",
                "执行 setup-podman 生成运行配置",
                "启动容器或 quadlet 服务",
                "验证 gateway.mode 与日志",
            ],
        ),
        DeployOption(
            option_id="macos-local",
            title="macOS 本机 + launchd",
            os_targets=["macos"],
            requires=["node", "git", "curl"],
            preferred_in=["global-open-likely", "mixed-uncertain"],
            description="macOS 本机常驻方案，使用 launchd/companion 生态。",
            risks=["需注意 profile 对应 launchd label", "权限与系统网络策略需校验"],
            steps=[
                "完成 onboard/configure",
                "执行 openclaw gateway install",
                "通过 openclaw gateway status 验证",
                "必要时使用 launchctl kickstart 对应服务",
            ],
        ),
        DeployOption(
            option_id="windows-wsl2",
            title="Windows + WSL2(Ubuntu) + systemd 用户服务",
            os_targets=["windows", "linux-wsl2"],
            requires=["node", "git", "curl", "systemd"],
            preferred_in=["global-open-likely", "mixed-uncertain"],
            description="Windows 推荐路径：在 WSL2 中按 Linux 方式运行 Gateway。",
            risks=["WSL 未启用 systemd 时服务托管失效", "主机与 WSL 网络映射需确认"],
            steps=[
                "启用 WSL2 与 Ubuntu 发行版",
                "在 WSL 启用 systemd 并重启 WSL",
                "在 WSL 内执行 Linux Node+systemd 部署步骤",
                "验证网关可达与日志",
            ],
        ),
    ]


def classify_os(os_info: Dict[str, Any]) -> str:
    sys_name = os_info.get("platform_system", "").lower()
    rel = os_info.get("os_release", {})
    distro_id = (rel.get("ID") or "").lower()
    is_wsl = bool(os_info.get("is_wsl"))

    if sys_name == "darwin":
        return "macos"
    if sys_name == "windows":
        return "windows"
    if sys_name == "linux":
        if is_wsl:
            return "linux-wsl2"
        if distro_id in {"ubuntu", "debian"}:
            return f"linux-{distro_id}"
        return "linux-other"
    return "unknown"


def evaluate_options(
    os_info: Dict[str, Any],
    tools: Dict[str, ToolCheck],
    net: Dict[str, Any],
) -> Dict[str, Any]:
    os_tag = classify_os(os_info)
    profile = net.get("profile", "mixed-uncertain")
    options = build_option_catalog()

    evaluated = []
    for opt in options:
        score = 0
        reasons = []
        gaps = []

        exact_match = os_tag in opt.os_targets
        linux_family_match = os_tag.startswith("linux") and any(t.startswith("linux") for t in opt.os_targets)

        if exact_match:
            score += 40
            reasons.append(f"匹配当前系统：{os_tag}")
        elif linux_family_match:
            score += 20
            reasons.append("同属 Linux 家族，存在迁移可行性")

        if profile in opt.preferred_in:
            score += 25
            reasons.append(f"匹配网络画像：{profile}")

        for req in opt.requires:
            if req == "systemd":
                ok = bool(os_info.get("systemd", {}).get("available"))
            else:
                ok = bool(tools.get(req) and tools[req].found)
            if ok:
                score += 5
            else:
                gaps.append(req)

        if not gaps:
            score += 10

        applicable = score >= 35
        evaluated.append(
            {
                "option": asdict(opt),
                "score": score,
                "applicable": applicable,
                "reasons": reasons,
                "gaps": gaps,
                "os_exact_match": exact_match,
                "linux_family_match": linux_family_match,
                "network_preferred": profile in opt.preferred_in,
            }
        )

    evaluated.sort(key=lambda x: x["score"], reverse=True)
    letter_map = assign_letters(evaluated)

    for item in evaluated:
        oid = item["option"]["option_id"]
        item["letter"] = letter_map.get(oid)

    recommended = evaluated[0] if evaluated else None
    alternatives = evaluated[1:4] if len(evaluated) > 1 else []

    return {
        "os_tag": os_tag,
        "recommended": recommended,
        "alternatives": alternatives,
        "all": evaluated,
        "letter_map": letter_map,
    }


def assign_letters(evaluated: List[Dict[str, Any]]) -> Dict[str, str]:
    mapping: Dict[str, str] = {}
    for idx, item in enumerate(evaluated):
        if idx >= len(string.ascii_uppercase):
            break
        mapping[item["option"]["option_id"]] = string.ascii_uppercase[idx]
    return mapping


def dependency_auto_fixable(dep: str, os_tag: str) -> Tuple[bool, str]:
    if dep == "systemd":
        return False, "systemd 依赖发行版/启动方式，不建议自动改造"

    linux_auto = {"git", "curl", "python3", "node", "npm", "docker", "podman", "ssh", "pnpm", "bun"}
    macos_auto = {"git", "curl", "python3", "node", "npm", "pnpm", "bun"}

    if os_tag in {"linux-ubuntu", "linux-debian", "linux-wsl2"}:
        if dep in linux_auto:
            return True, "可通过 apt（及对应官方源/镜像）补齐"
    if os_tag == "macos":
        if dep in macos_auto:
            return True, "可通过 Homebrew 补齐"

    return False, "需人工判断安装路径或当前平台不支持自动补齐"


def analyze_selected_option(report: Dict[str, Any], selected: Dict[str, Any]) -> Dict[str, Any]:
    option = selected["option"]
    os_tag = report["evaluation"]["os_tag"]
    net_profile = report["network"]["profile"]

    required = option.get("requires", [])
    satisfied: List[Dict[str, Any]] = []
    missing: List[Dict[str, Any]] = []
    auto_fixable: List[Dict[str, Any]] = []
    manual_only: List[Dict[str, Any]] = []

    tools = report["tools"]
    os_info = report["os"]

    for dep in required:
        if dep == "systemd":
            ok = bool(os_info.get("systemd", {}).get("available"))
            detail = "检测到 systemctl" if ok else "未检测到 systemctl"
        else:
            ok = bool(tools.get(dep, {}).get("found"))
            detail = tools.get(dep, {}).get("version") or tools.get(dep, {}).get("path") or "未检测到"

        dep_item = {
            "name": dep,
            "display": TOOL_CN_NAME.get(dep, dep),
            "ok": ok,
            "detail": detail,
        }

        if ok:
            satisfied.append(dep_item)
        else:
            af, af_reason = dependency_auto_fixable(dep, os_tag)
            dep_item["auto_fixable"] = af
            dep_item["auto_fix_reason"] = af_reason
            missing.append(dep_item)
            if af:
                auto_fixable.append(dep_item)
            else:
                manual_only.append(dep_item)

    os_supported = bool(selected.get("os_exact_match") or selected.get("linux_family_match"))
    network_risky = net_profile == "network-degraded" or (
        net_profile == "cn-restricted-likely" and "global-open-likely" in option.get("preferred_in", [])
    )

    if not os_supported:
        status = "unsupported"
        status_reason = "当前系统与该方案目标平台不匹配"
    elif manual_only:
        status = "unsupported"
        status_reason = "存在不可自动补齐依赖，需要人工处理"
    elif network_risky:
        status = "risky"
        status_reason = "网络画像显示部署风险较高，建议先处理网络可达性"
    elif not missing:
        status = "ready"
        status_reason = "该方案关键依赖已满足，可进入部署执行阶段（当前仅渲染）"
    else:
        status = "remediable"
        status_reason = "存在缺失项，但可自动补齐"

    return {
        "selected": selected,
        "status": status,
        "status_reason": status_reason,
        "os_supported": os_supported,
        "network_profile": net_profile,
        "satisfied": satisfied,
        "missing": missing,
        "auto_fixable": auto_fixable,
        "manual_only": manual_only,
    }


def build_remediation_plan(analysis: Dict[str, Any], report: Dict[str, Any]) -> List[str]:
    os_tag = report["evaluation"]["os_tag"]
    steps: List[str] = [
        f"当前状态：{analysis['status']}（{analysis['status_reason']}）",
        "以下补齐计划仅为建议，不会自动执行。",
    ]

    if not analysis["missing"]:
        steps.append("无需补齐：该方案依赖已满足。")
        return steps

    if analysis["auto_fixable"]:
        names = "、".join(x["display"] for x in analysis["auto_fixable"])
        steps.append(f"可自动补齐项：{names}")
        if os_tag in {"linux-ubuntu", "linux-debian", "linux-wsl2"}:
            bins = " ".join(x["name"] for x in analysis["auto_fixable"] if x["name"] != "systemd")
            if bins:
                steps.append(f"建议命令（Linux 示例）：sudo apt-get update && sudo apt-get install -y {bins}")
        elif os_tag == "macos":
            bins = " ".join(x["name"] for x in analysis["auto_fixable"] if x["name"] != "systemd")
            if bins:
                steps.append(f"建议命令（macOS 示例）：brew install {bins}")

    if analysis["manual_only"]:
        names = "、".join(x["display"] for x in analysis["manual_only"])
        steps.append(f"不可自动补齐项：{names}")
        for item in analysis["manual_only"]:
            steps.append(f"- {item['display']}: {item.get('auto_fix_reason', '需人工处理')}")

    steps.append("补齐完成后，重新执行 choose <选项> --plan-only 复检状态。")
    return steps


def build_deploy_plan(analysis: Dict[str, Any], report: Dict[str, Any]) -> List[str]:
    selected = analysis["selected"]
    option = selected["option"]
    gaps = [x["display"] for x in analysis["missing"]]

    steps: List[str] = [
        f"已选择方案：{selected['letter']} / {option['option_id']}（{option['title']}）",
        f"状态判定：{analysis['status']}（{analysis['status_reason']}）",
        f"系统标签：{report['evaluation']['os_tag']}，网络画像：{report['network']['profile']}",
    ]

    if gaps:
        steps.append("前置缺口：" + "、".join(gaps))
    else:
        steps.append("前置检查：关键依赖已满足")

    steps.extend(option.get("steps", []))
    steps.append("执行前闸门：确认不会误暴露网关监听，且鉴权已配置")
    steps.append("执行后验证：openclaw gateway status / openclaw logs --follow")
    steps.append("注意：当前 advisor 仅输出计划，不会执行上述动作")
    return steps


def render_script(title: str, intro: str, steps: List[str], command_hints: List[str]) -> str:
    lines = [
        "#!/usr/bin/env bash",
        "set -euo pipefail",
        "",
        f"# {title}",
        "# 仅渲染脚本，不执行真实部署/安装/重启",
        "",
        f"echo '[PLAN] {intro}'",
    ]

    for i, step in enumerate(steps, 1):
        esc = step.replace("'", "'\"'\"'")
        lines.append(f"echo '{i}. {esc}'")

    lines.extend(["", "cat <<'CMD'", "# 以下是未来可执行命令模板（当前不执行）"])
    lines.extend([f"# {c}" for c in command_hints])
    lines.extend(["CMD", "", "echo '[PLAN] 结束。'", ""])
    return "\n".join(lines)


def detect_public_ip(timeout: float = DEFAULT_TIMEOUT) -> Optional[str]:
    urls = [
        "https://api.ipify.org",
        "https://ifconfig.me/ip",
    ]
    for url in urls:
        try:
            req = urllib.request.Request(
                url,
                method="GET",
                headers={"User-Agent": "openclaw-deploy-advisor/0.3"},
            )
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                ip = resp.read().decode("utf-8", errors="ignore").strip()
                if re.match(r"^\d{1,3}(?:\.\d{1,3}){3}$", ip):
                    return ip
        except Exception:
            continue
    return None


def is_apply_requested(args: argparse.Namespace) -> bool:
    return bool(
        getattr(args, "apply_remediation", False)
        or getattr(args, "apply_deploy", False)
    )


def resolve_apply_gate(
    apply_requested: bool,
    action: str,
    confirm_value: str,
    execute_flag: bool,
) -> Dict[str, Any]:
    expected = action
    normalized = (confirm_value or "").strip().lower()

    gate = {
        "action": action,
        "apply_requested": apply_requested,
        "confirm_expected": expected,
        "confirm_provided": normalized,
        "execute_flag": bool(execute_flag),
        "confirmed": normalized == expected,
        "allowed": False,
        "reason": "not-requested",
        "message": "",
    }

    if not apply_requested:
        gate["message"] = "未请求 apply，保持预演。"
        return gate

    if normalized != expected:
        gate["reason"] = "confirm-required"
        gate["message"] = (
            f"{APPLY_PREVIEW_MSG} 本次 apply-{action} 需要 --confirm {expected}。"
        )
        return gate

    if not execute_flag:
        gate["reason"] = "execute-required"
        gate["message"] = (
            f"已确认 --confirm {expected}，但未提供 --execute，继续预演不执行。"
        )
        return gate

    gate["allowed"] = True
    gate["reason"] = "allowed"
    gate["message"] = f"确认通过：--confirm {expected} + --execute，进入真实执行。"
    return gate


def resolve_remediation_commands(analysis: Dict[str, Any], os_tag: str) -> List[str]:
    hints = REMEDIATION_COMMAND_HINTS.get(os_tag, {})
    cmds: List[str] = []
    missing = analysis.get("auto_fixable", [])

    if os_tag in {"linux-ubuntu", "linux-debian", "linux-wsl2"} and missing:
        cmds.append("sudo apt-get update")

    for item in missing:
        dep = item.get("name")
        cmd = hints.get(dep)
        if cmd and cmd not in cmds:
            cmds.append(cmd)

    return cmds


def run_apply_commands(commands: List[str], timeout: float = 600.0) -> List[Dict[str, Any]]:
    results: List[Dict[str, Any]] = []
    for cmd in commands:
        cp = subprocess.run(
            ["bash", "-lc", cmd],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            check=False,
        )
        results.append(
            {
                "command": cmd,
                "exit_code": cp.returncode,
                "stdout": cp.stdout.strip(),
                "stderr": cp.stderr.strip(),
                "ok": cp.returncode == 0,
            }
        )
        if cp.returncode != 0:
            break
    return results


def build_deploy_commands(selected: Dict[str, Any]) -> List[str]:
    option_id = selected["option"]["option_id"]
    base = [
        "openclaw onboard",
        "openclaw configure",
        "openclaw gateway install",
        "openclaw gateway status",
    ]

    if option_id == "ubuntu-docker-compose":
        return [
            "openclaw docker-setup",
            "docker compose up -d",
            "openclaw gateway status",
        ]

    if option_id == "ubuntu-podman-rootless":
        return [
            "openclaw setup-podman",
            "podman ps",
            "openclaw gateway status",
        ]

    return base


    lines: List[str] = []
    meta = report["meta"]
    osi = report["os"]
    net = report["network"]
    ev = report["evaluation"]

    lines.append(f"OpenClaw 部署顾问 v{meta['version']}")
    lines.append("=" * 58)
    lines.append(f"生成时间：{meta['generated_at']}")
    lines.append(f"系统：{osi['platform_system']} {osi['platform_release']} / {ev['os_tag']}")

    rel = osi.get("os_release", {})
    if rel:
        lines.append(
            "发行版："
            + " ".join(
                x
                for x in [rel.get("NAME"), rel.get("VERSION"), f"(ID={rel.get('ID')})"]
                if x
            )
        )

    lines.append(f"systemd：运行中={osi['systemd']['running']} 可用={osi['systemd']['available']}")

    lines.append("\n[网络画像]")
    lines.append(f"- 画像：{net['profile']}（{net['profile_reason']}）")
    lines.append(
        f"- global 可达：{net['summary']['global_ok']}/{net['summary']['global_total']}，cn 可达：{net['summary']['cn_ok']}/{net['summary']['cn_total']}"
    )

    lines.append("\n[工具检测]")
    order = ["node", "npm", "pnpm", "git", "ssh", "curl", "docker", "podman", "bun", "python3"]
    tools = report["tools"]
    for k in order:
        t = tools.get(k)
        if not t:
            continue
        cn = TOOL_CN_NAME.get(k, k)
        if t["found"]:
            lines.append(f"- {cn}: 已安装（{t['version'] or t['path']}）")
        else:
            lines.append(f"- {cn}: 缺失")

    lines.append("\n[候选部署方案（字母可直接用于 choose）]")
    for item in ev.get("all", []):
        opt = item["option"]
        letter = item.get("letter", "?")
        gaps = item.get("gaps", [])
        gap_cn = "、".join(TOOL_CN_NAME.get(x, x) for x in gaps) if gaps else "无"
        lines.append(
            f"- {letter}. {opt['title']} ({opt['option_id']}) | 分数={item['score']} | 缺口={gap_cn}"
        )

    if ev.get("recommended"):
        r = ev["recommended"]
        lines.append("\n[推荐方案]")
        lines.append(
            f"- 推荐：{r['letter']} / {r['option']['option_id']}（{r['option']['title']}），分数={r['score']}"
        )
        lines.append(f"- 说明：{r['option']['description']}")

    lines.append("\n[下一步]")
    lines.append("- 查看某方案缺口分析：choose A --plan-only")
    lines.append("- 渲染补齐脚本：choose A --render-remediation -")
    lines.append("- 渲染部署脚本：choose A --render-deploy -")

    if plan_only and ev.get("recommended"):
        lines.append("\n[推荐方案部署计划预览]")
        picked = ev["recommended"]
        analysis = analyze_selected_option(report, picked)
        for i, step in enumerate(build_deploy_plan(analysis, report), 1):
            lines.append(f"{i}. {step}")

    return "\n".join(lines) + "\n"


def to_text(report: Dict[str, Any], plan_only: bool = False) -> str:
    lines: List[str] = []
    meta = report["meta"]
    osi = report["os"]
    net = report["network"]
    ev = report["evaluation"]

    lines.append(f"OpenClaw 部署顾问 v{meta['version']}")
    lines.append("=" * 58)
    lines.append(f"生成时间：{meta['generated_at']}")
    lines.append(f"系统：{osi['platform_system']} {osi['platform_release']} / {ev['os_tag']}")

    rel = osi.get("os_release", {})
    if rel:
        lines.append(
            "发行版："
            + " ".join(
                x
                for x in [rel.get("NAME"), rel.get("VERSION"), f"(ID={rel.get('ID')})"]
                if x
            )
        )

    lines.append(f"systemd：运行中={osi['systemd']['running']} 可用={osi['systemd']['available']}")

    lines.append("\n[网络画像]")
    lines.append(f"- 画像：{net['profile']}（{net['profile_reason']}）")
    lines.append(
        f"- global 可达：{net['summary']['global_ok']}/{net['summary']['global_total']}，cn 可达：{net['summary']['cn_ok']}/{net['summary']['cn_total']}"
    )

    lines.append("\n[工具检测]")
    order = ["node", "npm", "pnpm", "git", "ssh", "curl", "docker", "podman", "bun", "python3"]
    tools = report["tools"]
    for k in order:
        t = tools.get(k)
        if not t:
            continue
        cn = TOOL_CN_NAME.get(k, k)
        if t["found"]:
            lines.append(f"- {cn}: 已安装（{t['version'] or t['path']}）")
        else:
            lines.append(f"- {cn}: 缺失")

    lines.append("\n[候选部署方案（字母可直接用于 choose）]")
    for item in ev.get("all", []):
        opt = item["option"]
        letter = item.get("letter", "?")
        gaps = item.get("gaps", [])
        gap_cn = "、".join(TOOL_CN_NAME.get(x, x) for x in gaps) if gaps else "无"
        lines.append(
            f"- {letter}. {opt['title']} ({opt['option_id']}) | 分数={item['score']} | 缺口={gap_cn}"
        )

    if ev.get("recommended"):
        r = ev["recommended"]
        lines.append("\n[推荐方案]")
        lines.append(
            f"- 推荐：{r['letter']} / {r['option']['option_id']}（{r['option']['title']}），分数={r['score']}"
        )
        lines.append(f"- 说明：{r['option']['description']}")

    lines.append("\n[下一步]")
    lines.append("- 检测/推荐：report --plan-only")
    lines.append("- 选择方案并分析缺口：choose A --plan-only")
    lines.append("- 只渲染补齐脚本：choose A --render-remediation -")
    lines.append("- 只渲染部署脚本：choose A --render-deploy -")
    lines.append("- 真实执行补齐：choose A --apply-remediation --confirm remediation --execute")
    lines.append("- 真实执行部署：choose A --apply-deploy --confirm deploy --execute")

    if plan_only and ev.get("recommended"):
        lines.append("\n[推荐方案部署计划预览]")
        picked = ev["recommended"]
        analysis = analyze_selected_option(report, picked)
        for i, step in enumerate(build_deploy_plan(analysis, report), 1):
            lines.append(f"{i}. {step}")

    return "\n".join(lines) + "\n"


def build_report(timeout: float, plan_only: bool = False) -> Dict[str, Any]:
    os_info = detect_os()
    tools = detect_tools(timeout=min(timeout, 3.0))
    net = detect_network(timeout=timeout)
    eval_res = evaluate_options(os_info, tools, net)

    report = {
        "meta": {
            "version": SCRIPT_VERSION,
            "generated_at": time.strftime("%Y-%m-%d %H:%M:%S %z"),
            "timeout_seconds": timeout,
            "plan_only": plan_only,
            "supports_apply": True,
            "description": "支持分阶段：检测/推荐、choose、依赖分析、remediation/deploy",
        },
        "os": os_info,
        "tools": {k: asdict(v) for k, v in tools.items()},
        "network": net,
        "evaluation": eval_res,
        "rules": {
            "network_profile": [
                "global-open-likely: global 可达率 >=80% 且 Telegram/Discord 可达",
                "cn-restricted-likely: cn 可达率高，global 可达率 <=50%，且 Telegram/Discord 至少一项不可达",
                "network-degraded: global/cn 均低可达",
                "mixed-uncertain: 其余混合状态",
            ],
            "recommendation_scoring": [
                "OS 精确匹配 +40，Linux 同族 +20",
                "网络画像匹配 +25",
                "每个已满足前置 +5",
                "无缺口额外 +10",
                "score>=35 视为可用候选",
            ],
            "status_levels": [
                "ready: 依赖齐全且无明显高风险",
                "remediable: 存在缺口但可自动补齐",
                "unsupported: 平台不匹配或存在不可自动补齐缺口",
                "risky: 网络或环境风险较高，建议先止血",
            ],
        },
    }
    return report


def parse_selection(selection: str, evaluation: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    s = selection.strip().upper()
    all_items = evaluation.get("all", [])

    if len(s) == 1 and s in string.ascii_uppercase:
        for item in all_items:
            if item.get("letter") == s:
                return item

    raw = selection.strip().lower()
    for item in all_items:
        if item["option"]["option_id"].lower() == raw:
            return item

    return None


def print_or_save(content: str, path: str) -> Dict[str, Any]:
    if path == "-":
        return {"content": content, "path": "-"}
    out_path = os.path.abspath(path)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(content)
    return {"path": out_path}


def cmd_choose(args: argparse.Namespace) -> int:
    report = build_report(timeout=args.timeout, plan_only=False)
    picked = parse_selection(args.selection, report["evaluation"])
    if not picked:
        payload = {
            "error": f"未找到选项：{args.selection}",
            "hint": "请使用 report 查看 A/B/C 映射，或传入 option-id",
        }
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return 2

    analysis = analyze_selected_option(report, picked)
    remediation_plan = build_remediation_plan(analysis, report)
    deploy_plan = build_deploy_plan(analysis, report)

    os_tag = report["evaluation"]["os_tag"]

    remediation_cmds = resolve_remediation_commands(analysis, os_tag)
    deploy_cmds = build_deploy_commands(picked)

    apply_remediation_requested = bool(getattr(args, "apply_remediation", False))
    apply_deploy_requested = bool(getattr(args, "apply_deploy", False))

    remediation_gate = resolve_apply_gate(
        apply_requested=apply_remediation_requested,
        action="remediation",
        confirm_value=getattr(args, "confirm", ""),
        execute_flag=bool(getattr(args, "execute", False)),
    )
    deploy_gate = resolve_apply_gate(
        apply_requested=apply_deploy_requested,
        action="deploy",
        confirm_value=getattr(args, "confirm", ""),
        execute_flag=bool(getattr(args, "execute", False)),
    )

    remediation_executed = []
    deploy_executed = []

    if remediation_gate["allowed"]:
        remediation_executed = run_apply_commands(remediation_cmds) if remediation_cmds else []

    if deploy_gate["allowed"]:
        deploy_executed = run_apply_commands(deploy_cmds) if deploy_cmds else []

    apply_result: Dict[str, Any] = {
        "remediation": {
            "requested": apply_remediation_requested,
            "executed": remediation_gate["allowed"],
            "requested_commands": remediation_cmds,
            "executed_commands": remediation_executed,
            "gate": remediation_gate,
        },
        "deploy": {
            "requested": apply_deploy_requested,
            "executed": deploy_gate["allowed"],
            "requested_commands": deploy_cmds,
            "executed_commands": deploy_executed,
            "gate": deploy_gate,
        },
    }

    will_execute = bool(remediation_gate["allowed"] or deploy_gate["allowed"])

    apply_messages: List[str] = []
    if apply_remediation_requested and remediation_gate.get("message"):
        apply_messages.append(f"[apply-remediation] {remediation_gate['message']}")
    if apply_deploy_requested and deploy_gate.get("message"):
        apply_messages.append(f"[apply-deploy] {deploy_gate['message']}")

    result: Dict[str, Any] = {
        "mode": "choose",
        "dry_run": not will_execute,
        "will_execute": will_execute,
        "selection": args.selection,
        "selected_letter": picked.get("letter"),
        "selected_option_id": picked["option"]["option_id"],
        "selected_title": picked["option"]["title"],
        "status": analysis["status"],
        "status_reason": analysis["status_reason"],
        "dependency_analysis": {
            "satisfied": analysis["satisfied"],
            "missing": analysis["missing"],
            "auto_fixable": analysis["auto_fixable"],
            "manual_only": analysis["manual_only"],
        },
        "remediation_plan": remediation_plan,
        "deploy_plan": deploy_plan,
        "apply": apply_result,
        "apply_messages": apply_messages,
        "next_actions": [
            "choose A --plan-only",
            "choose A --render-remediation -",
            "choose A --render-deploy -",
            "choose A --apply-remediation --confirm remediation --execute",
            "choose A --apply-deploy --confirm deploy --execute",
        ],
    }

    if args.render_remediation:
        rem_script = render_script(
            title="OpenClaw Advisor 补齐计划渲染",
            intro="依赖补齐步骤预览（render）",
            steps=remediation_plan,
            command_hints=remediation_cmds
            or [
                "sudo apt-get update",
                "sudo apt-get install -y <缺失依赖>",
                "./scripts/openclaw-deploy-advisor.py choose A --plan-only",
            ],
        )
        out = print_or_save(rem_script, args.render_remediation)
        if "content" in out:
            result["rendered_remediation_script"] = out["content"]
        else:
            result["rendered_remediation_script_path"] = out["path"]

    if args.render_deploy:
        dep_script = render_script(
            title="OpenClaw Advisor 部署计划渲染",
            intro="部署步骤预览（render）",
            steps=deploy_plan,
            command_hints=deploy_cmds,
        )
        out = print_or_save(dep_script, args.render_deploy)
        if "content" in out:
            result["rendered_deploy_script"] = out["content"]
        else:
            result["rendered_deploy_script_path"] = out["path"]

    if args.format == "json":
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0

    print(f"[choose] 已选择：{picked.get('letter')} / {picked['option']['option_id']}")
    print(f"状态：{analysis['status']}（{analysis['status_reason']}）")

    print("\n[已满足项]")
    if analysis["satisfied"]:
        for item in analysis["satisfied"]:
            print(f"- {item['display']}：{item['detail']}")
    else:
        print("- 无")

    print("\n[缺失项]")
    if analysis["missing"]:
        for item in analysis["missing"]:
            auto = "可自动补齐" if item.get("auto_fixable") else "不可自动补齐"
            print(f"- {item['display']}：{auto}（{item.get('auto_fix_reason','')}）")
    else:
        print("- 无")

    print("\n[补齐计划]")
    for i, s in enumerate(remediation_plan, 1):
        print(f"{i}. {s}")

    print("\n[部署计划]")
    for i, s in enumerate(deploy_plan, 1):
        print(f"{i}. {s}")

    if apply_remediation_requested:
        print("\n[apply-remediation]")
        print(f"- {remediation_gate['message']}")
        print("- 待执行命令：")
        if remediation_cmds:
            for cmd in remediation_cmds:
                print(f"  - {cmd}")
        else:
            print("  - （无可执行命令）")
        if remediation_gate["allowed"]:
            print("- 已进入真实执行路径。")

    if apply_deploy_requested:
        print("\n[apply-deploy]")
        print(f"- {deploy_gate['message']}")
        print("- 待执行命令：")
        if deploy_cmds:
            for cmd in deploy_cmds:
                print(f"  - {cmd}")
        else:
            print("  - （无可执行命令）")
        if deploy_gate["allowed"]:
            print("- 已进入真实执行路径。")

    print("\n[风险提示]")
    for r in picked["option"].get("risks", []):
        print(f"- {r}")

    if args.render_remediation:
        if args.render_remediation == "-":
            print("\n--- 补齐脚本渲染 ---")
            print(result.get("rendered_remediation_script", ""))
        else:
            print(f"\n补齐脚本已写入：{result.get('rendered_remediation_script_path')}")

    if args.render_deploy:
        if args.render_deploy == "-":
            print("\n--- 部署脚本渲染 ---")
            print(result.get("rendered_deploy_script", ""))
        else:
            print(f"\n部署脚本已写入：{result.get('rendered_deploy_script_path')}")

    if args.plan_only:
        print("\n下一步：可继续 render 或 apply。")

    return 0


def cmd_apply(args: argparse.Namespace) -> int:
    # 兼容旧接口，行为等同 choose <option-id> --apply-deploy
    args.selection = args.option_id
    args.render_remediation = ""
    args.render_deploy = args.render_script
    args.apply_remediation = False
    args.apply_deploy = True
    return cmd_choose(args)


def cmd_report(args: argparse.Namespace) -> int:
    report = build_report(timeout=args.timeout, plan_only=args.plan_only)
    if args.format == "json":
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print(to_text(report, plan_only=args.plan_only))
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="OpenClaw 部署顾问（交互增强版；支持检测、渲染与真实执行）"
    )
    p.add_argument("--format", choices=["text", "json"], default="text")
    p.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT, help="网络探测单请求超时秒数")

    sub = p.add_subparsers(dest="subcmd")

    p_report = sub.add_parser("report", help="检测环境并输出部署建议")
    p_report.add_argument("--plan-only", action="store_true", help="附带推荐方案计划预览")

    p_choose = sub.add_parser("choose", help="按字母或 option-id 选择方案并输出缺口分析/计划")
    p_choose.add_argument("selection", help="方案选择：A/B/C... 或 option-id")
    p_choose.add_argument("--plan-only", action="store_true", help="强调输出计划，不执行动作")
    p_choose.add_argument("--render-remediation", default="", help="渲染补齐计划脚本；传 '-' 直接输出")
    p_choose.add_argument("--render-deploy", default="", help="渲染部署计划脚本；传 '-' 直接输出")
    p_choose.add_argument("--apply-remediation", action="store_true", help="请求执行 remediation（需 --confirm remediation 与 --execute）")
    p_choose.add_argument("--apply-deploy", action="store_true", help="请求执行 deploy（需 --confirm deploy 与 --execute）")
    p_choose.add_argument(
        "--confirm",
        choices=["remediation", "deploy"],
        default="",
        help="执行确认闸门：apply-remediation 用 remediation，apply-deploy 用 deploy",
    )
    p_choose.add_argument(
        "--execute",
        action="store_true",
        help="二次确认开关；仅在 --confirm 匹配时才进入真实执行",
    )

    p_apply = sub.add_parser("apply", help="兼容旧命令：等同 choose <option-id>")
    p_apply.add_argument("option_id", help="方案 ID，如 ubuntu-systemd-node")
    p_apply.add_argument("--render-script", default="", help="兼容参数：等同 --render-deploy")
    p_apply.add_argument(
        "--confirm",
        choices=["deploy"],
        default="",
        help="apply 兼容入口确认参数：仅支持 deploy",
    )
    p_apply.add_argument(
        "--execute",
        action="store_true",
        help="二次确认开关；与 --confirm deploy 共同生效",
    )

    p.add_argument("--plan-only", action="store_true", help="默认 report 附带计划预览")

    return p


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    if not args.subcmd:
        args.subcmd = "report"

    if args.subcmd == "report":
        return cmd_report(args)
    if args.subcmd == "choose":
        return cmd_choose(args)
    if args.subcmd == "apply":
        return cmd_apply(args)

    parser.print_help()
    return 1


if __name__ == "__main__":
    sys.exit(main())
