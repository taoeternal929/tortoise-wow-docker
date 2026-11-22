#!/usr/bin/env python3
"""Database checks for the CI workflow. Run from the repo root.

  dbtest.py stack --image-repo R --tag T
      Start mariadb (from this repo's dump) plus the realmd and mangosd images,
      and check that realmd serves logins and mangosd gets through connecting to
      all four databases. mangosd then stops at "map files not found", because CI
      has no game client data; that point is expected and counts as a pass.

  dbtest.py migrations --previous DIR [--report FILE]
      Simulate a server upgrade: start mariadb from the dump, apply the
      migrations in DIR (the repo before the sync) as an up-to-date server
      would have, then apply what the sync changed. Migrations are run exactly
      like mangosd's DB auto-updater does it (same statement splitter, one
      transaction per file, skip files whose hash is already recorded), so a
      failure here is a failure mangosd would hit at startup.

Only the Python standard library is used.
"""
import argparse
import hashlib
import os
import re
import subprocess
import sys
import time
from pathlib import Path

UPDATES = Path("data/database_updates")
# folder -> mangosd.conf key, in the order mangosd's auto-updater processes them
FOLDERS = [("auth", "LoginDatabase.Info"), ("character", "CharacterDatabase.Info"), ("world", "WorldDatabase.Info")]


def sh(cmd, **kw):
    print("+", " ".join(cmd), flush=True)
    return subprocess.run(cmd, check=True, **kw)


def compose(*args, env=None, **kw):
    return sh(["docker", "compose", *args], env={**os.environ, **(env or {})}, **kw)


def start_db(timeout=900):
    # The compose file keeps the database in ./data/mysql. In a real server
    # checkout that is the live database, so never run against it: only a clean
    # checkout (as in CI) gets a fresh database imported from the dump.
    mysql = Path("data/mysql")
    if mysql.is_dir() and any(mysql.iterdir()):
        sys.exit("data/mysql is not empty. This test imports a fresh database from the dump and "
                 "applies migrations to it, so it only runs in a clean checkout (CI does that).")
    if not Path(".env").exists():
        # CI has no .env; the example's placeholder values are fine for a throwaway database.
        Path(".env").write_text(Path(".env.example").read_text())
        print("created .env from .env.example", flush=True)
    for d in ("mysql", "dbc", "maps", "vmaps", "mmaps", "patches"):
        (Path("data") / d).mkdir(parents=True, exist_ok=True)
    compose("up", "-d", "--build", "mariadb")
    deadline = time.time() + timeout
    while time.time() < deadline:
        state = subprocess.run(["docker", "inspect", "-f", "{{.State.Health.Status}}", "mariadb"],
                               capture_output=True, text=True).stdout.strip()
        if state == "healthy":
            print(f"mariadb healthy after {int(timeout - (deadline - time.time()))}s", flush=True)
            return
        if state == "unhealthy":
            break
        time.sleep(5)
    subprocess.run(["docker", "logs", "--tail", "50", "mariadb"])
    sys.exit("mariadb did not become healthy")


def logs(name):
    r = subprocess.run(["docker", "logs", name], capture_output=True, text=True)
    return (r.stdout + r.stderr).replace("\r", "")


def cmd_stack(a):
    env = {"TW_IMAGE_REPO": a.image_repo, "TW_IMAGE_TAG": a.tag}
    start_db()
    compose("up", "-d", "--no-build", "realmd", "mangosd", env=env)
    want = {
        "wow-realmd": "Login server is up and running",
        # Printed once mangosd has connected to the login, world, character and
        # logs databases and started world initialisation.
        "wow-mangosd": "Welcome to Turtle WoW! Realm ID",
    }
    bad = re.compile(r"Cannot connect|Can't connect|Could not connect|Access denied|AutoUpdater FAILED|"
                     r"error while loading shared libraries|Segmentation fault")
    deadline = time.time() + 180
    ok = {}
    while time.time() < deadline and len(ok) < len(want):
        for name, line in want.items():
            text = logs(name)
            if line in text:
                ok[name] = True
            m = bad.search(text)
            if m:
                print(text[-3000:])
                sys.exit(f"{name}: '{m.group(0)}' in log")
        time.sleep(3)
    for name in want:
        print(f"----- {name} (last lines)")
        print("\n".join(logs(name).strip().splitlines()[-12:]))
    problems = [f"did not reach the expected startup line: {n}" for n in want if n not in ok]
    problems += check_realm_id() + check_access()
    compose("down", env=env)
    if problems:
        sys.exit("stack test failed:\n  " + "\n  ".join(problems))
    print("stack test passed")


def env_file():
    vals = {}
    for line in Path(".env").read_text().splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            k, v = line.split("=", 1)
            vals[k.strip()] = v.strip()
    return vals


def check_realm_id():
    """mangosd.conf's RealmID must be a row in realmlist, and mangosd must use it."""
    m = re.search(r"^\s*RealmID\s*=\s*(\d+)", Path("mangosd/mangosd.conf").read_text(), re.M)
    if not m:
        return ["RealmID not found in mangosd/mangosd.conf"]
    rid = m.group(1)
    r = mariadb("tw_logon", f"SELECT name FROM realmlist WHERE id = {rid};")
    out = []
    if r.returncode or not r.stdout.strip():
        ids = mariadb("tw_logon", "SELECT GROUP_CONCAT(id) FROM realmlist;").stdout.strip()
        out.append(f"RealmID = {rid} in mangosd.conf, but realmlist only has id(s) {ids}")
    else:
        print(f"realm id check: RealmID {rid} is realmlist row '{r.stdout.strip()}'")
    if f"Realm ID: {rid}" not in logs("wow-mangosd"):
        out.append(f"mangosd did not report 'Realm ID: {rid}'")
    return out


def check_access():
    """Each database login may do only what it needs (see mariadb/init/03-users.sh)."""
    e = env_file()
    cases = [  # (user, password, sql, should_succeed)
        (e["MYSQL_USER"], e["MYSQL_PASSWORD"], "SELECT 1 FROM tw_world.migrations LIMIT 1", True),
        (e["MYSQL_USER"], e["MYSQL_PASSWORD"], "SELECT 1 FROM mysql.user LIMIT 1", False),
        (e["REGISTRATION_DB_USER"], e["REGISTRATION_DB_PASSWORD"], "SELECT COUNT(*) FROM tw_logon.account", True),
        (e["REGISTRATION_DB_USER"], e["REGISTRATION_DB_PASSWORD"], "SELECT 1 FROM tw_world.migrations LIMIT 1", False),
        (e["REGISTRATION_DB_USER"], e["REGISTRATION_DB_PASSWORD"], "DELETE FROM tw_logon.account WHERE 0", False),
        ("root", e["MYSQL_ROOT_PASSWORD"], "SELECT 1", False),   # no root over the network
    ]
    out = []
    for user, pw, sql, should in cases:
        # Over the network from another container, like realmd, mangosd and the portal.
        r = subprocess.run(["docker", "compose", "run", "--rm", "--no-deps", "-T", "--entrypoint", "mariadb",
                            "-e", f"MYSQL_PWD={pw}", "realmlist", "-h", "mariadb", f"-u{user}", "-e", sql],
                           capture_output=True, text=True)
        ok = r.returncode == 0
        print(f"access check: {user}: {sql} -> {'allowed' if ok else 'denied'}")
        if ok != should:
            out.append(f"{user} should {'be able to' if should else 'NOT be able to'} run: {sql}")
    return out


# --- migrations -------------------------------------------------------------

def split_like_autoupdater(sql: str):
    """Port of AutoUpdater::ExecuteUpdate's splitter (src/shared/Database/AutoUpdater.cpp).

    Returns (queries, unterminated_string). Kept deliberately literal, quirks
    included, so CI accepts and rejects exactly what mangosd does.
    """
    queries, q = [], []
    string = None      # None, "'" or '"'
    comment = None     # None, "line" or "block"
    n = len(sql)
    for i, ch in enumerate(sql):
        if ch in "\r\n":
            if ch == "\n":
                q.append(" ")
            if comment == "line":
                comment = None
            continue
        if ch == "/":
            if comment == "block" and i > 0 and sql[i - 1] == "*":
                comment = None
                continue
            if i < n - 1 and string is None and sql[i + 1] == "*":
                comment = "block"
                continue
        if comment is not None:
            continue
        if ch == "-" and i < n - 1 and string is None and sql[i + 1] == "-":
            comment = "line"
            continue
        if ch == "'":
            if string is None:
                string = "'"
            elif string == "'" and sql[i - 1] != "\\":
                string = None
        if ch == '"':
            if string is None:
                string = '"'
            elif string == '"' and sql[i - 1] != "\\":
                string = None
        q.append(ch)
        if ch == ";" and string is None:
            queries.append("".join(q))
            q = []
    rest = "".join(q)
    if rest.strip("\t\r\n "):
        queries.append(rest)
    return queries, string is not None


def conf_db(key):
    text = Path("mangosd/mangosd.conf").read_text(errors="replace")
    m = re.search(rf"^\s*{re.escape(key)}\s*=\s*\"([^\"]+)\"", text, re.M)
    return m.group(1).split(";")[-1]


def mariadb(db, stdin: str):
    # mangosd sends the file's bytes unchanged over a connection set to utf8
    # (utf8mb3). Latin-1 round-trips every byte, so this does the same.
    r = subprocess.run(
        ["docker", "compose", "exec", "-T", "mariadb", "sh", "-c",
         f'mariadb -uroot -p"$MYSQL_ROOT_PASSWORD" --default-character-set=utf8mb3 '
         f'--batch --skip-column-names {db}'],
        input=stdin.encode("latin-1"), capture_output=True)
    r.stdout = r.stdout.decode("utf-8", errors="replace")
    r.stderr = r.stderr.decode("utf-8", errors="replace")
    return r


def applied_hashes(db):
    r = mariadb(db, "CREATE TABLE IF NOT EXISTS `migrations` (`Id` INT UNSIGNED NOT NULL AUTO_INCREMENT,"
                    " `Name` VARCHAR(255) NOT NULL DEFAULT '0', `Module` VARCHAR(255) NOT NULL DEFAULT '',"
                    " `Hash` VARCHAR(128) NOT NULL DEFAULT '0', `AppliedAt` DATETIME NOT NULL,"
                    " PRIMARY KEY (`Id`)); SELECT `Hash` FROM `migrations` WHERE `Module` = '';")
    if r.returncode:
        sys.exit(f"cannot read {db}.migrations: {r.stderr.strip()}")
    return set(r.stdout.split())


def apply_dir(root: Path):
    """Apply every not-yet-recorded migration under root, like the auto-updater.
    Returns a list of (folder/file, ok, message)."""
    results = []
    for folder, key in FOLDERS:
        d = root / folder
        if not d.is_dir():
            continue
        db = conf_db(key)
        done = applied_hashes(db)
        for f in sorted(d.glob("*.sql"), key=lambda p: p.stem):   # Database.AutoUpdate.SortByName = 1
            data = f.read_bytes()
            h = hashlib.sha1(data).hexdigest().upper()
            if h in done:
                continue
            # The C++ splitter works on raw bytes and only looks at ASCII
            # characters; Latin-1 maps bytes 1:1, so splitting is identical.
            queries, unterminated = split_like_autoupdater(data.decode("latin-1"))
            label = f"{folder}/{f.name}"
            if unterminated:
                results.append((label, False, "file ends inside a quoted string"))
                continue
            # Same statements, one per line, inside one transaction, then the
            # bookkeeping row the auto-updater writes on success.
            body = "".join(qq.strip().rstrip(";").strip() + "@@TWEND@@\n" for qq in queries if qq.strip().rstrip(";").strip())
            script = (f"DELIMITER @@TWEND@@\nSTART TRANSACTION@@TWEND@@\n{body}"
                      f"INSERT INTO `migrations` (`Name`,`Module`,`Hash`,`AppliedAt`) VALUES ('{f.stem}','','{h}',NOW())@@TWEND@@\n"
                      "COMMIT@@TWEND@@\n")
            r = mariadb(db, script)
            if r.returncode == 0:
                done.add(h)
                results.append((label, True, ""))
            else:
                msg = (r.stderr.strip().splitlines() or ["unknown error"])[-1]
                results.append((label, False, msg[:300]))
    return results


def cmd_migrations(a):
    start_db()
    before = apply_dir(Path(a.previous))
    pre_fail = [r for r in before if not r[1]]
    after = apply_dir(UPDATES)
    failed = [r for r in after if not r[1]]

    lines = ["### Database check", ""]
    lines.append("Started MariaDB from `mariadb/init`'s dump, brought it to the previous version "
                 f"({len(before)} migration(s) not in the dump), then applied this PR's changes "
                 "the way mangosd's auto-updater does.")
    lines.append("")
    if not after:
        lines.append("No migrations to apply.")
    elif failed:
        lines.append(f"❌ **{len(failed)} of {len(after)} migration(s) failed.** A server upgrading to this "
                     "version would stop at startup on the first one (mangosd's auto-updater aborts).")
    else:
        lines.append(f"✅ All {len(after)} migration(s) applied cleanly.")
    lines.append("")
    for label, ok, msg in after:
        lines.append(f"- {'✅' if ok else '❌'} `{label}`" + (f": {msg}" if msg else ""))
    if pre_fail:
        lines += ["", f"⚠️ {len(pre_fail)} migration(s) from the previous version already fail on a fresh "
                      "install from the dump (not caused by this PR):", ""]
        lines += [f"- `{label}`: {msg}" for label, _, msg in pre_fail]
    report = "\n".join(lines) + "\n"
    print(report)
    if a.report:
        with open(a.report, "a") as fh:
            fh.write("\n" + report)
    compose("down")
    if a.fail_on_error and failed:
        sys.exit(1)


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("stack")
    s.add_argument("--image-repo", required=True)
    s.add_argument("--tag", required=True)
    m = sub.add_parser("migrations")
    m.add_argument("--previous", required=True)
    m.add_argument("--report")
    m.add_argument("--fail-on-error", action="store_true")
    a = p.parse_args()
    {"stack": cmd_stack, "migrations": cmd_migrations}[a.cmd](a)


if __name__ == "__main__":
    main()
