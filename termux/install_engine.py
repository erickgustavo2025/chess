# Python / install_engine.py / Python 3.10+ / official Stockfish 19 installer.
import hashlib
import os
import platform
import shutil
import tarfile
import tempfile
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RELEASE = 'sf_19'
ASSETS = {
    'android-arm64': ('stockfish-android-arm64-universal.tar.gz', 'ebb24051aa4a222b4daaf049b882ecf1163d370c128fe02316602643f4d5e426'),
    'android-armv7': ('stockfish-android-armv7-neon.tar.gz', '47c34963f1cdf4a6af34c1b5294f7a4e2679b3eb52698c324855af2c6486024b'),
    'linux-arm64': ('stockfish-linux-arm64-universal.tar.gz', 'fe26cfd1d9db4c8af3d21e24d9ff34cacb31c1f940085a7583da11796f2bac01'),
    'linux-x64': ('stockfish-linux-x86-64-universal.tar.gz', '9defc0d4e55d49c65a6d042f3e571a39fcea499ade6dbe741b53b8c65e03611f'),
    'macos': ('stockfish-macos-universal.tar.gz', 'a1f0e3bcc5a6927a11fe6fc8e54a779754645f3c2bae2cf13420fd1957adaa77'),
    'windows-x64': ('stockfish-windows-x86-64-universal.zip', '3c8bf1f9ea66a09350a40df4f632288285ac206d99f33ab5842c408fc30b48a7'),
    'windows-arm64': ('stockfish-windows-arm64-universal.zip', '8372ad3f0d7276deb2c70f801f541ec7db463219fc6d9c7592864e542aa4f401'),
}


def asset_key():
    machine = platform.machine().lower()
    arch = 'arm64' if machine in ('aarch64', 'arm64') else 'x64' if machine in ('x86_64', 'amd64') else 'armv7'
    if 'com.termux' in os.environ.get('PREFIX', '') or hasattr(os, 'getandroidapilevel'):
        return 'android-' + arch
    system = platform.system()
    if system == 'Darwin':
        return 'macos'
    if system == 'Windows':
        return 'windows-' + arch
    if system == 'Linux' and arch != 'armv7':
        return 'linux-' + arch
    raise RuntimeError(f'Plataforma não suportada: {system}/{machine}')


def download(url, target):
    request = urllib.request.Request(url, headers={'User-Agent': 'ChessHint/2.0'})
    with urllib.request.urlopen(request, timeout=60) as source, target.open('wb') as dest:
        shutil.copyfileobj(source, dest)


def install():
    name, expected = ASSETS[asset_key()]
    target = ROOT / 'bin' / ('stockfish.exe' if name.endswith('.zip') else 'stockfish')
    marker = target.with_suffix('.release')
    if target.is_file() and marker.is_file() and marker.read_text().strip() == expected:
        print('Stockfish 19 já instalado:', target)
        return target
    target.parent.mkdir(exist_ok=True)
    print('Baixando Stockfish 19 oficial; primeira instalação pode demorar...', flush=True)
    with tempfile.TemporaryDirectory(dir=ROOT) as folder:
        archive = Path(folder) / name
        download(f'https://github.com/official-stockfish/Stockfish/releases/download/{RELEASE}/{name}', archive)
        with archive.open('rb') as source:
            digest = hashlib.file_digest(source, 'sha256').hexdigest() if hasattr(hashlib, 'file_digest') else hashlib.sha256(source.read()).hexdigest()
        if digest != expected:
            raise RuntimeError('SHA256 do Stockfish não corresponde à versão oficial')
        temporary = Path(folder) / target.name
        if name.endswith('.zip'):
            with zipfile.ZipFile(archive) as package:
                binaries = [m for m in package.infolist() if m.filename.endswith('.exe') and Path(m.filename).name.startswith('stockfish')]
                if len(binaries) != 1:
                    raise RuntimeError('Arquivo oficial sem binário único')
                with package.open(binaries[0]) as source, temporary.open('wb') as dest:
                    shutil.copyfileobj(source, dest)
        else:
            with tarfile.open(archive, 'r:gz') as package:
                binaries = [m for m in package.getmembers() if m.isfile() and
                            Path(m.name).name.startswith('stockfish-') and '.' not in Path(m.name).name]
                if len(binaries) != 1:
                    raise RuntimeError('Arquivo oficial sem binário único')
                with package.extractfile(binaries[0]) as source, temporary.open('wb') as dest:
                    shutil.copyfileobj(source, dest)
        temporary.chmod(0o755)
        os.replace(temporary, target)
        marker.write_text(expected + '\n')
    print('Instalado:', target, flush=True)
    return target


if __name__ == '__main__':
    install()
