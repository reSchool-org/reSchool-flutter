#!/usr/bin/env python3
"""проверяем индекс git на секреты и артефакты, сами значения не выводим; история сюда не входит"""
from pathlib import PurePosixPath
import re
import subprocess
import sys


def main():
    paths = subprocess.check_output(["git", "ls-files", "-z"]).decode().split("\0")
    forbidden_parts = {"node_modules", ".wrangler", "__pycache__", ".dart_tool", "Pods", "secrets"}
    forbidden_suffixes = {".p8", ".p12", ".pfx", ".key", ".pem", ".mobileprovision",
                          ".provisionprofile", ".jks", ".keystore", ".ipa", ".dmg", ".apk"}
    signatures = [rb"-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----(?:\\n|\r?\n)[A-Za-z0-9+/]{20,}",
                  rb'"type"\s*:\s*"service_account"',
                  rb"gh[pousr]_[A-Za-z0-9]{30,}", rb"github_pat_[A-Za-z0-9_]{40,}",
                  rb"\b[0-9]{8,12}:[A-Za-z0-9_-]{35}\b"]
    failed = []
    for name in filter(None, paths):
        path = PurePosixPath(name)
        prohibited = (set(path.parts) & forbidden_parts or path.suffix in forbidden_suffixes
                      or path.name in {"GoogleService-Info.plist", "google-services.json", "session.json", "eschool_session.json"}
                      or (path.name.startswith((".env", ".dev.vars")) and not path.name.endswith(".example")))
        # читаем блобы из индекса, рабочая копия может отличаться
        blob = subprocess.check_output(["git", "show", f":{name}"])
        if prohibited or any(re.search(pattern, blob) for pattern in signatures):
            failed.append(name)
    if failed:
        print("Refusing publication; review these paths (values redacted):", file=sys.stderr)
        for name in failed:
            print(name, file=sys.stderr)
        return 1
    print("Index guard passed: no recognized private keys, tokens or forbidden artifacts.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
