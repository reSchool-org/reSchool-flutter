#!/usr/bin/env python3
"""сборка apple идёт на временном раннере github, закрытые ключи не экспортируем"""

import argparse
import base64
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = "com.magisky.reschoolbeta"
GROUP = "group.com.magisky.reschoolbeta"
TARGETS = ("ios-testflight", "macos-testflight", "macos-direct")
SECRET_PREFIXES = ("APPLE_", "ASC_")
MACOS_BUILD_SETTINGS = ("SDKROOT=macosx", "SUPPORTED_PLATFORMS=macosx",
                        "SUPPORTS_MACCATALYST=NO", "ARCHS=arm64 x86_64",
                        "ONLY_ACTIVE_ARCH=NO", "EXCLUDED_ARCHS=")


def run(*args, cwd=ROOT, capture=False, capture_stderr=False, extra_env=None):
    # фазы сборки и утилиты зависимостей исходные секреты не наследуют
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(SECRET_PREFIXES)}
    env.update(extra_env or {})
    result = subprocess.run(args, cwd=cwd, env=env, check=False,
                            stdout=subprocess.PIPE if capture else None,
                            stderr=(subprocess.STDOUT if capture_stderr else subprocess.PIPE) if capture else None)
    if result.returncode:
        # в аргументах бывают пароли от связки ключей, в ошибки их не тащим
        raise RuntimeError(f"{Path(args[0]).name} failed (exit {result.returncode})")
    return result.stdout if capture else b""


def submit_to_testflight(artifact, platform, key_id, issuer, state):
    # Xcode 26 altool can exit zero after an Apple rejection. Require the
    # operation's success acknowledgement, including output written to stderr.
    for operation, verb, legacy in (("--validate-app", "VERIFY", "validating"),
                                    ("--upload-app", "UPLOAD", "uploading")):
        output = run("xcrun", "altool", operation, "--file", str(artifact), "--type", platform,
                     "--apiKey", key_id, "--apiIssuer", issuer, "--output-format", "normal",
                     capture=True, capture_stderr=True,
                     extra_env={"API_PRIVATE_KEYS_DIR": str(state)}).decode("utf-8", errors="replace")
        print(output, flush=True)
        failed = re.search(r"\b(?:VERIFY FAILED|UPLOAD FAILED|ERROR|Validation failed|Failed to (?:validate|upload))\b",
                           output, re.IGNORECASE)
        succeeded = re.search(rf"\b{verb} SUCCEEDED\b|\bNo errors {legacy} (?:archive|package)\b", output)
        if failed or not succeeded:
            raise RuntimeError(f"altool {operation}: Apple did not confirm success")


def secret(name):
    value = os.environ.get(name, "")
    if not value:
        raise ValueError(f"Missing required secret: {name}")
    return value


def decode(name, destination):
    try:
        data = base64.b64decode("".join(secret(name).split()), validate=True)
    except ValueError:
        raise ValueError(f"Invalid base64 in {name}") from None
    destination.write_bytes(data)
    destination.chmod(0o600)
    return destination


def version_values(version, build):
    if not re.fullmatch(r"\d{1,3}\.\d{1,3}\.\d{1,3}", version):
        raise ValueError("Version must be numeric MAJOR.MINOR.PATCH")
    if not re.fullmatch(r"[1-9]\d{0,8}", build):
        raise ValueError("Build must be a positive integer of at most 9 digits")
    # в CFBundleVersion apple разрешает всего 4, 2 и 2 цифры,
    # связка run_number и run_attempt растёт монотонно, даже если перезапускать
    number = int(build)
    if number > 99989999:
        raise ValueError("Build counter exceeds Apple's supported range")
    return version, f"{number // 10000 + 1}.{number // 100 % 100}.{number % 100}"


def prepare(platform, version, build, unsigned):
    lock = ROOT / platform / "Podfile.lock"
    locked_contents = lock.read_bytes()
    args = ["flutter", "build", platform, "--release", "--config-only",
            "--no-pub", f"--build-name={version}", f"--build-number={build}"]
    if platform == "ios":
        args.append("--no-codesign")
    run(*args)
    if lock.read_bytes() != locked_contents:
        if not unsigned:
            raise ValueError("Flutter changed Podfile.lock; regenerate and review it in unsigned CI first")
        print("::warning::Podfile.lock changed; review the dependency-locks artifact before release")
    run("pod", "install", "--deployment", cwd=ROOT / platform)


def profile_values(data, bundle, platform, team, direct, identity=None):
    entitlements = data.get("Entitlements", {})
    identifier = entitlements.get("application-identifier",
                                  entitlements.get("com.apple.application-identifier", ""))
    prefixes = data.get("ApplicationIdentifierPrefix", [])
    if not any(identifier == f"{prefix}.{bundle}" for prefix in prefixes):
        raise ValueError("Provisioning profile bundle ID mismatch")
    if team not in data.get("TeamIdentifier", []):
        raise ValueError("Provisioning profile team mismatch")
    if data.get("ExpirationDate", datetime.datetime.min) <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
        raise ValueError("Provisioning profile expired")
    expected_platform = "iOS" if platform == "ios" else "OSX"
    if expected_platform not in data.get("Platform", []):
        raise ValueError("Provisioning profile platform mismatch")
    if entitlements.get("get-task-allow") or entitlements.get("com.apple.security.get-task-allow"):
        raise ValueError("Development provisioning profiles cannot be released")
    if data.get("ProvisionedDevices") or (data.get("ProvisionsAllDevices") and not direct):
        raise ValueError("Use App Store Connect distribution profiles, not ad-hoc/enterprise")
    if GROUP not in entitlements.get("com.apple.security.application-groups", []):
        raise ValueError("Provisioning profile is missing the shared App Group")
    # настройка профилей сама сверяет отпечаток sha256 до того, как импортирует личность
    if identity is not None and not any(
            isinstance(cert, bytes) and hashlib.sha1(cert).hexdigest().upper() == identity.upper()
            for cert in data.get("DeveloperCertificates", [])):
        raise ValueError("Provisioning profile does not include the selected signing certificate")
    uuid = data.get("UUID", "")
    if not re.fullmatch(r"[A-Fa-f0-9-]{36}", uuid):
        raise ValueError("Invalid provisioning profile UUID")
    return uuid


def signing_identity(keychain, team, allowed, policy="codesigning"):
    identities = run("security", "find-identity", "-v", "-p", policy,
                     str(keychain), capture=True).decode()
    matches = [sha for sha, name in re.findall(r'([A-Fa-f0-9]{40}) "([^"]+)"', identities)
               if name.startswith(allowed) and name.endswith(f"({team})")]
    if len(matches) != 1:
        raise ValueError("Import exactly one matching distribution signing identity with private key")
    return matches[0]


def verify_native_macos(bundle, data):
    if (data.get("CFBundleSupportedPlatforms") != ["MacOSX"]
            or data.get("DTPlatformName") != "macosx"
            or not data.get("DTSDKName", "macosx").startswith("macosx")
            or data.get("DTPlatformVariant", "") not in ("", "macos")
            or any(key.startswith("UI") or key in ("LSRequiresIPhoneOS", "MinimumOSVersion")
                   for key in data)):
        raise ValueError("Expected native MacOSX bundle metadata, not iOS or Mac Catalyst")
    executable = data.get("CFBundleExecutable", "")
    if not executable or Path(executable).name != executable:
        raise ValueError("Invalid macOS bundle executable")
    binary = bundle / "Contents/MacOS" / executable
    if not binary.is_file():
        raise ValueError("Missing macOS bundle executable")
    arches = run("lipo", "-archs", str(binary), capture=True).decode().split()
    if set(arches) != {"arm64", "x86_64"}:
        raise ValueError("macOS app and widget must be universal arm64 + x86_64")
    for arch in ("arm64", "x86_64"):
        output = run("xcrun", "vtool", "-arch", arch, "-show-build",
                     str(binary), capture=True).decode()
        commands = re.split(r"^\s*cmd\s+", output, flags=re.MULTILINE)[1:]
        if not commands:
            raise ValueError("Missing macOS Mach-O platform load command")
        for command in commands:
            kind = command.split()[0]
            platforms = re.findall(r"^\s*platform\s+(\S+)", command, re.MULTILINE)
            # intel срезы под старые macos описывают минимальную версию старой командой
            if not (kind == "LC_VERSION_MIN_MACOSX" or
                    (kind == "LC_BUILD_VERSION" and platforms in (["MACOS"], ["1"]))):
                raise ValueError("Mach-O slice is not native macOS")


def verify_app(app, platform, version, build, signed):
    bundles = [app, *app.rglob("*.appex")]
    if len(bundles) != 2:
        raise ValueError("Expected an app with exactly one widget extension")
    for bundle in bundles:
        info = bundle / ("Info.plist" if platform == "ios" else "Contents/Info.plist")
        data = plistlib.loads(info.read_bytes())
        expected = BUNDLE if bundle == app else BUNDLE + (
            ".ReSchoolWidgets" if platform == "ios" else ".ReSchoolMacWidgets")
        if data.get("CFBundleIdentifier") != expected:
            raise ValueError("Built bundle identifier mismatch")
        if (data.get("CFBundleShortVersionString"), data.get("CFBundleVersion")) != (version, build):
            raise ValueError("App and widget versions must match the release")
        if platform == "macos":
            verify_native_macos(bundle, data)
            if bundle == app and data.get("LSApplicationCategoryType") != "public.app-category.education":
                raise ValueError("macOS app must declare the education category")
        manifest = bundle / ("PrivacyInfo.xcprivacy" if platform == "ios"
                             else "Contents/Resources/PrivacyInfo.xcprivacy")
        if not manifest.is_file():
            raise ValueError("Missing first-party privacy manifest")
        if signed:
            run("codesign", "--verify", "--deep", "--strict", str(bundle))
            ent = plistlib.loads(run("codesign", "-d", "--entitlements", ":-",
                                    str(bundle), capture=True))
            if ent.get("get-task-allow") or ent.get("com.apple.security.get-task-allow"):
                raise ValueError("Release contains debug entitlements")
            if GROUP not in ent.get("com.apple.security.application-groups", []):
                raise ValueError("Signed bundle lost its App Group")
            if platform == "macos" and not ent.get("com.apple.security.app-sandbox"):
                raise ValueError("macOS release must retain its sandbox")
            # The app no longer requests push notifications. If APNs is enabled
            # again, a release must still never carry the development entitlement.
            if platform == "ios" and bundle == app and ent.get("aps-environment") not in (None, "production"):
                raise ValueError("Enabled iOS release APNs must use production")


def verify_pkg(artifact, version, build, state):
    run("pkgutil", "--check-signature", str(artifact))
    with tempfile.TemporaryDirectory(prefix="pkg-", dir=state) as temporary:
        expanded = Path(temporary) / "expanded"
        run("pkgutil", "--expand-full", str(artifact), str(expanded))
        # считаем только установленные бандлы из Payload, метаданные из Scripts не трогаем
        apps = [app for app in expanded.rglob("*.app")
                if "Payload" in app.relative_to(expanded).parts
                and "Scripts" not in app.relative_to(expanded).parts
                and (app / "Contents/Info.plist").is_file()]
        if len(apps) != 1:
            raise ValueError("Expected exactly one app in the exported macOS PKG payload")
        verify_app(apps[0], "macos", version, build, signed=True)


def notarize(artifact, staple_target, key, key_id, issuer):
    output = run("xcrun", "notarytool", "submit", str(artifact),
        "--key", str(key), "--key-id", key_id, "--issuer", issuer,
        "--wait", "--output-format", "json", capture=True)
    try:
        result = json.loads(output)
    except ValueError:
        raise ValueError("Invalid notarization response") from None
    if not isinstance(result, dict):
        raise ValueError("Invalid notarization response")
    submission = result.get("id", "")
    valid_id = isinstance(submission, str) and re.fullmatch(
        r"[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}", submission)
    if result.get("status") != "Accepted" or not valid_id:
        if valid_id:
            print(f"Notarization submission ID: {submission}")
        raise ValueError("Apple notarization did not accept the artifact; inspect the submission in notarytool")
    run("xcrun", "stapler", "staple", str(staple_target))
    run("xcrun", "stapler", "validate", str(staple_target))
    if staple_target.suffix == ".app":
        run("spctl", "--assess", "--type", "execute", "--verbose", str(staple_target))
    else:
        run("spctl", "--assess", "--type", "open", "--context", "context:primary-signature",
            "--verbose", str(staple_target))
    return submission


def release(args, version, build):
    platform = args.target.split("-")[0]
    direct = args.target == "macos-direct"
    team = secret("APPLE_TEAM_ID")
    if not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise ValueError("Invalid Apple Team ID")
    # если только собираем и экспортируем, авторизация для загрузки не нужна
    if args.upload or direct:
        for name in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY_BASE64"):
            secret(name)
    for name in ("APPLE_CERTIFICATE_P12_BASE64", "APPLE_CERTIFICATE_P12_PASSWORD",
                 "APPLE_APP_PROFILE_BASE64", "APPLE_WIDGET_PROFILE_BASE64"):
        secret(name)
    if args.target == "macos-testflight":
        secret("APPLE_INSTALLER_P12_BASE64")
        secret("APPLE_INSTALLER_P12_PASSWORD")
    # сначала проверяем зависимости, и только потом открываем доступ к подписи
    prepare(platform, version, build, unsigned=False)
    state = Path(os.environ["RUNNER_TEMP"]) / "reschool-apple-signing"
    state.mkdir(mode=0o700)  # состояние подписи от чужого запуска переиспользовать нельзя
    keychain = state / "release.keychain-db"
    installed = []
    original_keychains = run("security", "list-keychains", "-d", "user", capture=True)
    (state / "keychains.json").write_text(json.dumps(re.findall(r'"([^"]+)"', original_keychains.decode())))
    try:
        password = base64.b64encode(os.urandom(32)).decode()
        run("security", "create-keychain", "-p", password, str(keychain), capture=True)
        run("security", "set-keychain-settings", "-lut", "21600", str(keychain), capture=True)
        run("security", "unlock-keychain", "-p", password, str(keychain), capture=True)
        for prefix in (["APPLE_CERTIFICATE"] if args.target != "macos-testflight"
                       else ["APPLE_CERTIFICATE", "APPLE_INSTALLER"]):
            p12 = decode(prefix + "_P12_BASE64", state / f"{prefix}.p12")
            run("security", "import", str(p12), "-k", str(keychain), "-P",
                secret(prefix + "_P12_PASSWORD"), "-T", "/usr/bin/codesign",
                "-T", "/usr/bin/productbuild", "-T", "/usr/bin/productsign", capture=True)
            p12.unlink()
        run("security", "list-keychains", "-d", "user", "-s", str(keychain),
            *json.loads((state / "keychains.json").read_text()), capture=True)
        run("security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:",
            "-k", password, str(keychain), capture=True)
        allowed = ("Developer ID Application:" if direct else "Apple Distribution:",)
        if args.target == "macos-testflight":
            allowed += ("3rd Party Mac Developer Application:",)
        identity = signing_identity(keychain, team, allowed)
        if args.target == "macos-testflight":
            installer = signing_identity(keychain, team,
                ("3rd Party Mac Developer Installer:", "Mac Installer Distribution:"), policy="basic")
        profiles = {}
        for name, bundle in (("Runner", BUNDLE),
                             ("ReSchoolWidgets" if platform == "ios" else "ReSchoolMacWidgets",
                              BUNDLE + (".ReSchoolWidgets" if platform == "ios" else ".ReSchoolMacWidgets"))):
            profile = decode("APPLE_APP_PROFILE_BASE64" if name == "Runner"
                             else "APPLE_WIDGET_PROFILE_BASE64", state / f"{name}.profile")
            data = plistlib.loads(run("security", "cms", "-D", "-i", str(profile), capture=True))
            uuid = profile_values(data, bundle, platform, team, direct, identity)
            # xcode начиная с 16 берёт каталог Developer, но путь MobileDevice
            # оставляем ради инструментов, которые всё ещё ищут там
            for directory in ("Library/Developer/Xcode/UserData/Provisioning Profiles",
                              "Library/MobileDevice/Provisioning Profiles"):
                suffix = "mobileprovision" if platform == "ios" else "provisionprofile"
                dest = Path.home() / directory / f"{uuid}.{suffix}"
                dest.parent.mkdir(parents=True, exist_ok=True)
                if dest.exists():
                    raise ValueError("Refusing to overwrite an existing provisioning profile")
                shutil.copyfile(profile, dest)
                installed.append(str(dest))
                (state / "profiles.json").write_text(json.dumps(installed))
            profiles[name] = {"bundle": bundle, "uuid": uuid}
        config = state / "signing.json"
        config.write_text(json.dumps({"team": team, "identity": identity, "profiles": profiles}))
        run("ruby", str(ROOT / "deploy/configure_apple_signing.rb"), platform, str(config))
        archive = ROOT / "build/apple/Runner.xcarchive"
        destination = "generic/platform=iOS" if platform == "ios" else "generic/platform=macOS"
        run("xcodebuild", "-workspace", f"{platform}/Runner.xcworkspace", "-scheme", "Runner",
            "-configuration", "Release", "-destination", destination, "-archivePath", str(archive),
            f"FLUTTER_BUILD_NAME={version}", f"FLUTTER_BUILD_NUMBER={build}",
            "ENABLE_HARDENED_RUNTIME=YES", *(MACOS_BUILD_SETTINGS if platform == "macos" else ()), "archive")
        archived_apps = list((archive / "Products/Applications").glob("*.app"))
        if len(archived_apps) != 1:
            raise ValueError("Expected exactly one archived application")
        verify_app(archived_apps[0], platform, version, build, signed=True)
        options = {"method": "developer-id" if direct else "app-store-connect",
                   "destination": "export", "teamID": team, "signingStyle": "manual",
                   "signingCertificate": identity, "manageAppVersionAndBuildNumber": False,
                   "uploadSymbols": True, "stripSwiftSymbols": True,
                   "provisioningProfiles": {v["bundle"]: v["uuid"] for v in profiles.values()}}
        if args.target == "macos-testflight":
            options["installerSigningCertificate"] = installer
        export_options = state / "ExportOptions.plist"
        export_options.write_bytes(plistlib.dumps(options))
        export = ROOT / "build/apple/export"
        run("xcodebuild", "-exportArchive", "-archivePath", str(archive), "-exportPath", str(export),
            "-exportOptionsPlist", str(export_options))
        output = ROOT / "build/apple/artifacts"
        output.mkdir(parents=True, exist_ok=False)
        if args.upload or direct:
            key_id, issuer = secret("ASC_KEY_ID"), secret("ASC_ISSUER_ID")
            if not re.fullmatch(r"[A-Z0-9]{10}", key_id) or not re.fullmatch(r"[a-fA-F0-9-]{36}", issuer):
                raise ValueError("Invalid App Store Connect key/issuer ID")
            key = decode("ASC_PRIVATE_KEY_BASE64", state / f"AuthKey_{key_id}.p8")
        notarization_ids = {}
        if direct:
            apps = list(export.glob("*.app"))
            if len(apps) != 1:
                raise ValueError("Expected exactly one exported macOS app")
            app = apps[0]
            verify_app(app, platform, version, build, signed=True)
            app_zip = state / "notarize-app.zip"
            run("ditto", "-c", "-k", "--keepParent", str(app), str(app_zip))
            notarization_ids["app"] = notarize(app_zip, app, key, key_id, issuer)
            staging = state / "dmg"
            staging.mkdir()
            run("ditto", str(app), str(staging / app.name))
            (staging / "Applications").symlink_to("/Applications")
            artifact = output / f"reSchool-{version}-{build}.dmg"
            run("hdiutil", "create", "-volname", "reSchool", "-srcfolder", str(staging),
                "-format", "UDZO", str(artifact))
            run("codesign", "--sign", identity, "--timestamp", str(artifact))
            run("codesign", "--verify", "--strict", str(artifact))
            notarization_ids["dmg"] = notarize(artifact, artifact, key, key_id, issuer)
        else:
            suffix = "ipa" if platform == "ios" else "pkg"
            files = list(export.glob(f"*.{suffix}"))
            if len(files) != 1:
                raise ValueError(f"Expected exactly one exported {suffix}")
            artifact = output / f"reSchool-{platform}-{version}-{build}.{suffix}"
            shutil.copyfile(files[0], artifact)
            if platform == "macos":
                verify_pkg(artifact, version, build, state)
            else:
                unpacked = state / "ipa"
                run("ditto", "-x", "-k", str(artifact), str(unpacked))
                apps = list((unpacked / "Payload").glob("*.app"))
                if len(apps) != 1:
                    raise ValueError("Expected one app in the exported IPA")
                verify_app(apps[0], platform, version, build, signed=True)
        if args.upload and not direct:
            submit_to_testflight(artifact, platform, key_id, issuer, state)
        symbols = archive / "dSYMs"
        if symbols.is_dir():
            run("ditto", "-c", "-k", "--keepParent", str(symbols), str(output / "dSYMs.zip"))
        metadata = {"commit": os.environ.get("GITHUB_SHA"), "target": args.target,
                    "version": version, "build": build,
                    "artifact": artifact.name, "platform": platform, "native_macos": platform == "macos",
                    "uploaded_to_testflight": args.upload and not direct,
                    "notarized": direct, "app_notarized": direct,
                    "notarization_submission_ids": notarization_ids,
                    "sha256": hashlib.sha256(artifact.read_bytes()).hexdigest()}
        (output / "release.json").write_text(json.dumps(metadata, indent=2) + "\n")
        print("Release completed. Only distribution files, dSYMs and metadata are publishable.")
    finally:
        cleanup()


def cleanup():
    state = Path(os.environ["RUNNER_TEMP"]) / "reschool-apple-signing"
    if not state.exists():
        return
    failed = False
    if (state / "keychains.json").exists():
        try:
            run("security", "list-keychains", "-d", "user", "-s",
                *json.loads((state / "keychains.json").read_text()), capture=True)
        except RuntimeError:
            failed = True
    if (state / "release.keychain-db").exists():
        try:
            run("security", "delete-keychain", str(state / "release.keychain-db"), capture=True)
        except RuntimeError:
            failed = True
    for path in json.loads((state / "profiles.json").read_text()) if (state / "profiles.json").exists() else []:
        Path(path).unlink(missing_ok=True)
    # исходные ключи стираем, даже если запасной уборке придётся ещё раз лезть в связку
    for pattern in ("*.p8", "*.p12", "*.profile"):
        for path in state.glob(pattern):
            path.unlink(missing_ok=True)
    if failed:
        raise RuntimeError("Keychain cleanup failed; discard this runner")
    shutil.rmtree(state)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("unsigned", "release", "cleanup"))
    parser.add_argument("--target", choices=TARGETS, default="ios-testflight")
    parser.add_argument("--version", default="2.0.0")
    parser.add_argument("--build", default="1")
    parser.add_argument("--upload", action="store_true")
    args = parser.parse_args()
    if sys.platform != "darwin" or os.environ.get("GITHUB_ACTIONS") != "true":
        raise ValueError("This script is restricted to disposable GitHub-hosted macOS runners")
    os.umask(0o077)
    if args.command == "cleanup":
        cleanup()
        return
    version, build = version_values(args.version, args.build)
    if args.command == "release":
        release(args, version, build)
    else:
        platform = args.target.split("-")[0]
        prepare(platform, version, build, unsigned=True)
        destination = "generic/platform=iOS" if platform == "ios" else "generic/platform=macOS"
        run("xcodebuild", "-workspace", f"{platform}/Runner.xcworkspace", "-scheme", "Runner",
            "-configuration", "Release", "-destination", destination,
            "-derivedDataPath", str(ROOT / "build/apple/DerivedData"), "CODE_SIGNING_ALLOWED=NO",
            "CODE_SIGNING_REQUIRED=NO", f"FLUTTER_BUILD_NAME={version}",
            f"FLUTTER_BUILD_NUMBER={build}", *(MACOS_BUILD_SETTINGS if platform == "macos" else ()), "build")
        products = ROOT / "build/apple/DerivedData/Build/Products" / ("Release-iphoneos" if platform == "ios" else "Release")
        apps = list(products.glob("*.app"))
        if len(apps) != 1:
            raise ValueError("Expected exactly one unsigned application")
        verify_app(apps[0], platform, version, build, signed=False)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError) as error:
        print(f"::error::{error}", file=sys.stderr)
        sys.exit(1)
