"""Rebuild the legacy Flutter snapshot; require replacements for corrupt entries."""
import base64
import io
from pathlib import Path
import shutil
import zipfile

root = Path(__file__).resolve().parents[1]
target = root / 'app'
if target.exists():
    raise SystemExit('app/ already exists; use a fresh build directory.')
parts = sorted((root / 'build_src_v2_small').glob('part_*.b64'))
archive = zipfile.ZipFile(io.BytesIO(base64.b64decode(''.join(p.read_text() for p in parts))))
patches = [root / name / 'lib' for name in ('v3_patch', 'v4_patch', 'v5_patch', 'v7_patch', 'v10_patch')]
for entry in archive.infolist():
    path = Path(entry.filename)
    if path.is_absolute() or '..' in path.parts or path.parts[0] != 'maalish_app':
        raise SystemExit(f'Unexpected archive path: {entry.filename}')
    relative = Path(*path.parts[1:])
    destination = target / relative
    if entry.is_dir():
        destination.mkdir(parents=True, exist_ok=True)
        continue
    try:
        data = archive.read(entry)
    except zipfile.BadZipFile:
        if relative.parts[0] != 'lib' or not any((p / Path(*relative.parts[1:])).is_file() for p in patches):
            raise
        print(f'Using committed patch for corrupt archive entry: {relative}')
        continue
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(data)
for patch in patches:
    shutil.copytree(patch, target / 'lib', dirs_exist_ok=True)
print('Flutter sources reconstructed into app/.')
