#!/usr/bin/env python3
"""проверяем локальную подпись apple и загружаем её в секреты окружения"""

import argparse
import base64
import getpass
import json
from pathlib import Path
import re
import subprocess
import sys
import warnings


def command(*args, data=None):
    result = subprocess.run(args, input=data, capture_output=True, check=False)
    if result.returncode:
        # ни вывод, ни аргументы операций с кредами не печатаем
        raise RuntimeError(f"{Path(args[0]).name} failed; no secret values were printed")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--p12", type=Path, required=True)
    parser.add_argument("--repo", default="reSchool-org/reSchool-Flutter-test")
    parser.add_argument("--also-repo", help="Also upload the same identity to this owner/name repository")
    parser.add_argument("--environment", default="apple-ios-testflight")
    parser.add_argument("--kind", choices=("distribution", "developer-id", "installer"),
                        default="distribution")
    args = parser.parse_args()
    repositories = [args.repo] + ([args.also_repo] if args.also_repo is not None else [])
    if any(not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_][A-Za-z0-9_.-]*", repo)
           for repo in repositories):
        raise RuntimeError("Repositories must use owner/name format")
    if len({repo.lower() for repo in repositories}) != len(repositories):
        raise RuntimeError("Duplicate repository destinations are not allowed")
    destinations = {
        "distribution": ("apple-ios-testflight", "apple-macos-testflight"),
        "developer-id": ("apple-macos-direct",),
        "installer": ("apple-macos-testflight",),
    }
    if args.environment not in destinations[args.kind]:
        raise RuntimeError("Certificate kind does not match the destination Environment")
    names = {
        "distribution": ("Apple Distribution:",),
        "developer-id": ("Developer ID Application:",),
        "installer": ("3rd Party Mac Developer Installer:", "Mac Installer Distribution:"),
    }[args.kind]
    if args.kind == "distribution" and args.environment == "apple-macos-testflight":
        names += ("3rd Party Mac Developer Application:",)
    if not sys.stdin.isatty():
        raise RuntimeError("Run this command yourself in an interactive terminal for hidden password entry")
    if not args.p12.is_file() or args.p12.is_symlink():
        raise RuntimeError("Provide a regular local .p12 file, not a symbolic link")
    args.p12.chmod(0o600)
    encoded = base64.b64encode(args.p12.read_bytes())
    if len(encoded) > 48 * 1024:
        raise RuntimeError("The base64 file exceeds GitHub's 48 KiB secret limit; export only one identity")

    # проверяем все назначения до того, как что то спросим или запишем
    for repo in repositories:
        endpoint = f"repos/{repo}/environments/{args.environment}"
        environment = json.loads(command("gh", "api", endpoint))
        if environment.get("deployment_branch_policy") != {
            "protected_branches": False, "custom_branch_policies": True
        }:
            raise RuntimeError("Configure this Environment to allow only the main branch before uploading keys")
        policies = json.loads(command("gh", "api", endpoint + "/deployment-branch-policies"))
        branches = policies.get("branch_policies", [])
        if (policies.get("total_count") != 1 or len(branches) != 1
                or branches[0].get("name") != "main" or branches[0].get("type") != "branch"):
            raise RuntimeError("Expected exactly one Environment branch rule: main")
        print(f"Destination: {repo} / {args.environment}")
        if not any(rule.get("type") == "required_reviewers"
                   for rule in environment.get("protection_rules", [])):
            print("This Environment has no separate reviewer approval. Manual main-branch releases only.")
    warnings.simplefilter("error", getpass.GetPassWarning)
    password = getpass.getpass("Password for .p12 (hidden): ")
    if not password or "\n" in password or "\r" in password:
        raise RuntimeError("A nonempty, single-line .p12 password is required")
    password_input = password.encode("utf-8") + b"\n"

    # noout прячет само содержимое ключа, info показывает только структуру контейнера
    options = ["openssl", "pkcs12", "-in", str(args.p12), "-passin", "stdin"]
    result = subprocess.run([*options, "-info", "-noout"], input=password_input,
                            capture_output=True, check=False)
    if result.returncode and b"unsupported" in result.stderr.lower():
        options.append("-legacy")
        result = subprocess.run([*options, "-info", "-noout"], input=password_input,
                                capture_output=True, check=False)
    if result.returncode:
        raise RuntimeError("Cannot open .p12: check its password and format. Nothing was uploaded")
    if not re.search(rb"(?:Shrouded Keybag|Key bag)", result.stderr, re.IGNORECASE):
        raise RuntimeError("The .p12 has no private key. Export the certificate with its private key")
    certificates = command(*options, "-clcerts", "-nokeys", data=password_input)
    if certificates.count(b"-----BEGIN CERTIFICATE-----") != 1:
        raise RuntimeError("Export exactly one signing identity, not multiple certificates")
    subject = command("openssl", "x509", "-noout", "-subject", "-nameopt", "RFC2253",
                      data=certificates).decode().strip().removeprefix("subject=").strip()
    team = re.search(r"(?:^|(?<!\\),)OU=([A-Z0-9]{10})(?:,|$)", subject)
    if not any(re.search(r"(?:^|(?<!\\),)CN=" + re.escape(name), subject)
               for name in names) or not team:
        raise RuntimeError("Certificate common name does not match the selected kind")
    if team.group(1) != "AQ52Q995ZR":
        raise RuntimeError("Certificate team does not match this project's Apple team")
    command("openssl", "x509", "-noout", "-checkend", "0", data=certificates)

    print(f"{args.kind} certificate, expiry and private-key presence checked.")
    prefix = "APPLE_INSTALLER" if args.kind == "installer" else "APPLE_CERTIFICATE"
    values = {
        prefix + "_P12_BASE64": encoded,
        prefix + "_P12_PASSWORD": password.encode("utf-8"),
        "APPLE_TEAM_ID": team.group(1).encode("ascii"),
    }
    for repo in repositories:
        for name, value in values.items():
            command("gh", "secret", "set", name, "--repo", repo,
                    "--env", args.environment, data=value)
            print(f"Stored {name} in {repo}")
    print("Certificate setup complete. No release was started. Keep your .p12 backup secure.")


if __name__ == "__main__":
    try:
        main()
    except RuntimeError as error:
        print(f"Setup failed: {error}. If upload had already started, rerun to finish it.", file=sys.stderr)
        sys.exit(1)
    except (OSError, EOFError, ValueError, getpass.GetPassWarning):
        # подробности исключения не отдаём: в них могут оказаться входные данные
        print("Setup failed or was interrupted. No secret values were printed. "
              "Check the file/password, gh access and Environment rules; rerun to finish "
              "any partial upload.", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("Setup cancelled.", file=sys.stderr)
        sys.exit(130)
