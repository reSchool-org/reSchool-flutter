"""собираем сервер из текущих исходников, чтобы приложение ставило совместимую версию"""

import argparse
import gzip
import io
from pathlib import Path
import tarfile

ROOT = Path(__file__).resolve().parents[2]
SERVER = ROOT / 'server'
OUTPUT = ROOT / 'assets/cloud/server.tar.gz'


def package(check=False):
    files = [SERVER / name for name in ('VERSION', 'docker-compose.settings.yml', '.dockerignore', 'Dockerfile', 'docker-compose.yml', 'docker-compose.browser.yml', 'Caddyfile', 'entrypoint.sh', 'requirements.txt', 'deploy/cloud-bootstrap.sh')]
    files += [path for path in (SERVER / 'server_advanced').rglob('*') if path.is_file()
              and path.suffix in ('.py', '.sql') and '__pycache__' not in path.parts
              and 'runtime' not in path.parts and 'uploads' not in path.parts]
    files += [path for path in (SERVER / 'server_advanced/assets').rglob('*') if path.is_file() and path.suffix in ('.svg', '.js')]
    files += [path for path in (SERVER / 'browser_transport').iterdir() if path.is_file() and (path.suffix == '.py' or path.name in ('requirements.txt', 'Dockerfile'))]
    files += [path for path in (SERVER / 'settings_manager').iterdir() if path.suffix in ('.py', '.service')]
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode='w') as archive:
        for path in sorted(files):
            info = archive.gettarinfo(str(path), arcname=str(path.relative_to(SERVER)))
            info.mtime = 0
            info.uid = info.gid = 0
            info.uname = info.gname = ''
            info.mode = 0o755 if path.name == 'entrypoint.sh' else 0o644
            with path.open('rb') as source:
                archive.addfile(info, source)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    payload = gzip.compress(buffer.getvalue(), mtime=0)
    if check:
        if not OUTPUT.exists() or OUTPUT.read_bytes() != payload:
            raise SystemExit('Архив сервера устарел: python3 .github/scripts/package_cloud_server.py')
    else:
        OUTPUT.write_bytes(payload)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    package(check=parser.parse_args().check)
