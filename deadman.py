#!/usr/bin/env python3
"""Rex's Deadman Switch — cron, standard library only.

`deadman ping` checks in. If you miss N days, `deadman run` emails the
handoff notes to your contacts, once per silence. A later ping sends a
false alarm and arms it again.

    deadman init | ping | status | run [--dry-run] | test

Config: $DEADMAN_HOME or ~/.config/deadman/{config,state}.json
Cron:   0 8 * * * DEADMAN_HOME=$HOME/.config/deadman python3 $HOME/bin/deadman.py run
"""

from __future__ import annotations

import argparse, json, os, smtplib, sys
from datetime import datetime, timezone
from email.message import EmailMessage
from pathlib import Path

TEMPLATE = {
    "days": 14,
    "subject": "Handoff — Rex's deadman switch fired",
    "notes": "If you are reading this, I missed my check-in.\n\nStart here:\n- \n",
    "contacts": [{"name": "Backup", "email": "backup@example.com"}],
    "recall": True,
    "smtp": {"host": "smtp.example.com", "port": 587, "user": "", "password": "",
             "starttls": True, "from": "Rex <you@example.com>"},
}

def root() -> Path:
    return Path(os.environ.get("DEADMAN_HOME") or Path.home() / ".config" / "deadman")

def cfg_path() -> Path:
    return root() / "config.json"

def state_path() -> Path:
    return root() / "state.json"

def stamp(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def parse(s: str) -> datetime:
    return datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)

def load(path: Path):
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        return None

def save(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    os.chmod(path.parent, 0o700)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n")
    os.chmod(tmp, 0o600)
    tmp.replace(path)

def gone_days(state, now):
    last = state.get("last_ping")
    return None if not last else (now - parse(last)).total_seconds() / 86400.0

def due(cfg, state, now) -> str:
    gone = gone_days(state, now)
    if gone is None:
        return "unarmed"
    if gone < float(cfg["days"]):
        return "wait"
    if state.get("fired_for") == state.get("last_ping"):
        return "hold"
    return "fire"

def guard(cfg):
    people = cfg.get("contacts") or []
    if not people:
        return "no contacts"
    if any("@" not in (c.get("email") or "") for c in people):
        return "bad contact"
    if not str(cfg.get("notes") or "").strip():
        return "empty notes"
    return None

def message(cfg, kind: str) -> EmailMessage:
    msg = EmailMessage()
    msg["From"] = cfg["smtp"]["from"]
    msg["To"] = ", ".join(c["email"] for c in cfg["contacts"])
    if kind == "fire":
        msg["Subject"] = cfg["subject"]
        msg.set_content(str(cfg["notes"]).rstrip() + "\n")
    else:
        msg["Subject"] = "False alarm — " + cfg["subject"]
        msg.set_content("Disregard the handoff. I checked in.\nThe switch is armed again.\n")
    return msg

def send(cfg, msg: EmailMessage) -> None:
    smtp = cfg["smtp"]
    with smtplib.SMTP(smtp["host"], int(smtp["port"]), timeout=30) as sock:
        sock.ehlo()
        if smtp.get("starttls", True):
            sock.starttls()
            sock.ehlo()
        if smtp.get("user"):
            sock.login(smtp["user"], smtp.get("password") or "")
        sock.send_message(msg)

def need():
    cfg = load(cfg_path())
    if cfg is None:
        print("run deadman init first", file=sys.stderr)
    return cfg

def load_state():
    return load(state_path()) or {"last_ping": None, "fired_for": None}

def cmd_init(_a) -> int:
    if cfg_path().exists():
        print(f"already exists: {cfg_path()}", file=sys.stderr)
        return 1
    save(cfg_path(), TEMPLATE)
    save(state_path(), {"last_ping": None, "fired_for": None})
    print(f"wrote {cfg_path()}")
    print("edit days, contacts, notes, smtp — then deadman ping")
    return 0

def cmd_ping(_a) -> int:
    cfg = need()
    if cfg is None:
        return 1
    cur = load_state()
    had = bool(cur.get("fired_for"))
    cur["last_ping"] = stamp(datetime.now(timezone.utc))
    cur["fired_for"] = None
    save(state_path(), cur)
    print(f"ping {cur['last_ping']}  window {cfg['days']}d")
    if had and cfg.get("recall", True):
        send(cfg, message(cfg, "recall"))
        print("recall sent")
    return 0

def cmd_status(_a) -> int:
    cfg = need()
    if cfg is None:
        return 1
    cur, now = load_state(), datetime.now(timezone.utc)
    kind, gone = due(cfg, cur, now), gone_days(cur, now)
    if gone is None:
        print("unarmed — ping once")
    else:
        left = f"  {float(cfg['days']) - gone:.1f}d left" if kind == "wait" else ""
        print(f"silent {gone:.1f}d / {cfg['days']}d  ({kind}){left}")
    print(f"last_ping {cur.get('last_ping')}")
    print(f"fired_for {cur.get('fired_for')}")
    return 0

def cmd_run(args) -> int:
    cfg = need()
    if cfg is None:
        return 1
    cur = load_state()
    kind = due(cfg, cur, datetime.now(timezone.utc))
    if kind != "fire":
        print(kind)
        return 0
    if bad := guard(cfg):
        print(bad, file=sys.stderr)
        return 1
    msg = message(cfg, "fire")
    if args.dry_run:
        print(msg["Subject"])
        print(msg.get_content(), end="")
        return 0
    send(cfg, msg)
    cur["fired_for"] = cur["last_ping"]
    save(state_path(), cur)
    print(f"fired to {len(cfg['contacts'])}")
    return 0

def cmd_test(_a) -> int:
    cfg = need()
    if cfg is None:
        return 1
    if bad := guard(cfg):
        print(bad, file=sys.stderr)
        return 1
    msg = message(cfg, "fire")
    msg.replace_header("Subject", "[test] " + msg["Subject"])
    send(cfg, msg)
    print("test sent")
    return 0

def main(argv=None) -> int:
    p = argparse.ArgumentParser(prog="deadman", description="Rex's Deadman Switch")
    sub = p.add_subparsers(dest="cmd", required=True)
    for name, fn in (("init", cmd_init), ("ping", cmd_ping), ("status", cmd_status), ("test", cmd_test)):
        sub.add_parser(name).set_defaults(fn=fn)
    run = sub.add_parser("run")
    run.add_argument("--dry-run", action="store_true")
    run.set_defaults(fn=cmd_run)
    args = p.parse_args(argv)
    return args.fn(args)

if __name__ == "__main__":
    raise SystemExit(main())
