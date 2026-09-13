"""самоподписанный сертификат для работы без домена
приложение доверяет такому сертификату не по цепочке до корневого CA,
а по отпечатку публичного ключа, который владелец сервера переносит на телефон
вручную или ссылкой. Поэтому ключ бережём: пока он не меняется, отпечаток живёт"""

import base64
import datetime
import hashlib
import ipaddress
import os
import socket
import stat
from urllib.parse import quote

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID

from .config import RUNTIME_DIR

TLS_DIR = os.path.join(RUNTIME_DIR, "tls")
CERT_PATH = os.path.join(TLS_DIR, "cert.pem")
KEY_PATH = os.path.join(TLS_DIR, "key.pem")

# порт самоподписанного https, домен если он есть живёт отдельно на 443
TLS_PORT = int(os.getenv("TLS_PORT", "4443").strip() or "4443")

# сертификат живёт долго, перевыпуск ломает доверие на всех уже привязанных телефонах
_CERT_YEARS = 10
_RENEW_BEFORE_DAYS = 30


def _extra_sans():
    """адреса из TLS_SANS, если авто определение ошиблось или сервер за натом"""
    raw = os.getenv("TLS_SANS", "")
    return [item.strip() for item in raw.replace(";", ",").split(",") if item.strip()]


# у каждого контейнера свой адрес в докер сети, а сертификат на всех один:
# пустишь их в san, и каждый контейнер перевыпустит его под себя, а caddy
# останется отдавать тот, что загрузил при старте
_DOCKER_NET = ipaddress.ip_network("172.16.0.0/12")


def _is_container_ip(value):
    try:
        return ipaddress.ip_address(value) in _DOCKER_NET
    except ValueError:
        return False


def _local_ips():
    ips = set()

    # трюк с udp сокетом: до отправки дело не доходит, но ядро выбирает исходящий адрес
    for probe in (("8.8.8.8", 53), ("1.1.1.1", 53)):
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            sock.settimeout(1)
            sock.connect(probe)
            ips.add(sock.getsockname()[0])
        except OSError:
            pass
        finally:
            sock.close()

    try:
        for info in socket.getaddrinfo(socket.gethostname(), None):
            ips.add(info[4][0])
    except OSError:
        pass

    # адрес хоста в локальной сети изнутри контейнера не виден, его задают через TLS_SANS
    return {ip for ip in ips if not _is_container_ip(ip)}


def _public_ip():
    """белый ip спрашиваем снаружи, в докере локальный адрес всегда серый"""
    env_ip = os.getenv("SERVER_PUBLIC_IP", "").strip()
    if env_ip:
        return env_ip

    try:
        import requests

        response = requests.get("https://api.ipify.org", timeout=5)
        if response.status_code == 200:
            candidate = response.text.strip()
            ipaddress.ip_address(candidate)
            return candidate
    except Exception:
        pass
    return ""


def collect_addresses():
    """все адреса, которые стоит зашить в сертификат, публичный идёт первым"""
    ordered = []
    seen = set()

    for value in [_public_ip(), *_extra_sans(), *sorted(_local_ips()), "127.0.0.1", "localhost"]:
        value = (value or "").strip()
        if not value or value in seen:
            continue
        seen.add(value)
        ordered.append(value)

    return ordered


def _san_entries(addresses):
    entries = []
    for value in addresses:
        try:
            entries.append(x509.IPAddress(ipaddress.ip_address(value)))
        except ValueError:
            try:
                entries.append(x509.DNSName(value))
            except ValueError:
                continue
    return entries


def _load_cert():
    try:
        with open(CERT_PATH, "rb") as handle:
            return x509.load_pem_x509_certificate(handle.read())
    except Exception:
        return None


def _load_key():
    try:
        with open(KEY_PATH, "rb") as handle:
            return serialization.load_pem_private_key(handle.read(), password=None)
    except Exception:
        return None


def _cert_sans(cert):
    try:
        ext = cert.extensions.get_extension_for_class(x509.SubjectAlternativeName)
    except x509.ExtensionNotFound:
        return set()
    values = set()
    for name in ext.value:
        if isinstance(name, x509.IPAddress):
            values.add(str(name.value))
        elif isinstance(name, x509.DNSName):
            values.add(name.value)
    return values


def _needs_reissue(cert, key, addresses):
    if cert is None:
        return True

    # сертификат мог остаться от старого ключа, тогда caddy просто не поднимется
    if cert.public_key().public_numbers() != key.public_key().public_numbers():
        return True

    now = datetime.datetime.now(datetime.timezone.utc)
    not_after = cert.not_valid_after_utc if hasattr(cert, "not_valid_after_utc") else cert.not_valid_after
    if not_after.tzinfo is None:
        not_after = not_after.replace(tzinfo=datetime.timezone.utc)
    if not_after - now < datetime.timedelta(days=_RENEW_BEFORE_DAYS):
        return True

    # новый адрес это повод перевыпустить, ключ при этом останется прежним
    return not set(addresses).issubset(_cert_sans(cert))


def _build_cert(key, addresses):
    now = datetime.datetime.now(datetime.timezone.utc)
    subject = x509.Name([
        x509.NameAttribute(NameOID.COMMON_NAME, addresses[0] if addresses else "reschool-server"),
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, "reSchool"),
    ])

    builder = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(subject)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(minutes=5))
        .not_valid_after(now + datetime.timedelta(days=365 * _CERT_YEARS))
        .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
        .add_extension(
            x509.KeyUsage(
                digital_signature=True,
                key_encipherment=False,
                key_agreement=True,
                content_commitment=False,
                data_encipherment=False,
                key_cert_sign=False,
                crl_sign=False,
                encipher_only=False,
                decipher_only=False,
            ),
            critical=True,
        )
        .add_extension(
            x509.ExtendedKeyUsage([x509.oid.ExtendedKeyUsageOID.SERVER_AUTH]),
            critical=False,
        )
    )

    san = _san_entries(addresses)
    if san:
        builder = builder.add_extension(x509.SubjectAlternativeName(san), critical=False)

    return builder.sign(key, hashes.SHA256())


def ensure_certificate():
    """готовит пару ключ плюс сертификат, ключ переиспользуем, чтобы не слетал отпечаток"""
    os.makedirs(TLS_DIR, exist_ok=True)
    addresses = collect_addresses()

    key = _load_key()
    if key is None:
        key = ec.generate_private_key(ec.SECP256R1())
        with open(KEY_PATH, "wb") as handle:
            handle.write(
                key.private_bytes(
                    encoding=serialization.Encoding.PEM,
                    format=serialization.PrivateFormat.PKCS8,
                    encryption_algorithm=serialization.NoEncryption(),
                )
            )
        os.chmod(KEY_PATH, stat.S_IRUSR | stat.S_IWUSR | stat.S_IRGRP)

    cert = _load_cert()
    if _needs_reissue(cert, key, addresses):
        cert = _build_cert(key, addresses)
        with open(CERT_PATH, "wb") as handle:
            handle.write(cert.public_bytes(serialization.Encoding.PEM))
        os.chmod(CERT_PATH, 0o644)

    return cert


def public_key_pin(cert=None):
    """пин в формате sha256 от SubjectPublicKeyInfo, как в hpkp"""
    cert = cert or _load_cert()
    if cert is None:
        return ""
    spki = cert.public_key().public_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    return "sha256/" + base64.b64encode(hashlib.sha256(spki).digest()).decode()


def certificate_sha256(cert=None):
    """отпечаток всего сертификата, его же показывает openssl и браузеры"""
    cert = cert or _load_cert()
    if cert is None:
        return ""
    digest = hashlib.sha256(cert.public_bytes(serialization.Encoding.DER)).hexdigest().upper()
    return ":".join(digest[i:i + 2] for i in range(0, len(digest), 2))


def tls_status():
    """то, что сервер отдаёт приложению в /config"""
    cert = _load_cert()
    if cert is None:
        return {"tlsPin": "", "tlsFingerprint": "", "tlsPort": TLS_PORT}
    return {
        "tlsPin": public_key_pin(cert),
        "tlsFingerprint": certificate_sha256(cert),
        "tlsPort": TLS_PORT,
    }


def connection_hint(api_token=""):
    """текст со ссылкой для привязки, его печатаем в лог при старте"""
    cert = _load_cert()
    if cert is None:
        return "TLS сертификат не сгенерирован"

    addresses = [
        value for value in collect_addresses()
        if value not in {"127.0.0.1", "localhost"} and not value.startswith("172.")
    ]
    host = addresses[0] if addresses else "127.0.0.1"
    base = f"https://{host}:{TLS_PORT}"
    pin = public_key_pin(cert)

    link = f"reschool://link-device?server={base}&pin={quote(pin, safe='')}"
    if api_token:
        link += f"&token={api_token}"

    lines = [
        "",
        "=" * 72,
        " reSchool работает без домена, на самоподписанном сертификате",
        "=" * 72,
        f" адрес сервера:  {base}",
        f" отпечаток ключа: {pin}",
        f" сертификат sha256: {certificate_sha256(cert)}",
        "",
        " перенесите на телефон эту ссылку, приложение запомнит отпечаток:",
        f" {link}",
        "",
        " либо вбейте адрес руками, приложение покажет отпечаток и попросит сверить",
        "=" * 72,
        "",
    ]
    return "\n".join(lines)


if __name__ == "__main__":
    ensure_certificate()
    print(connection_hint(os.getenv("API_TOKEN", "")))
