#!/usr/bin/env python3
"""Run only in the isolated root SDK; never creates a real installed profile."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

assert os.getuid() == 0 and not Path('/dev/snd').exists()
base = Path(__file__).resolve().parent
source = base.parent / 'src'
root = Path(tempfile.mkdtemp(prefix='elementary-eq-profile-', dir='/root'))
directory = root / 'v1'
directory.mkdir()
profile = directory / 'fixture-v1.ini'
checks = {}
try:
    flags = subprocess.check_output(['pkg-config', '--cflags', '--libs', 'gio-2.0'], text=True).split()
    subprocess.run(['cc', '-Wall', '-Wextra', '-Wno-unused-parameter', '-I'+str(source), '-DGETTEXT_PACKAGE="io.elementary.settings-daemon"',
                    '-DEQ_PROFILE_DIR='+json.dumps(str(directory)), str(base/'profile-file.c'),
                    str(source/'Backends/speaker-equalizer-profile.c'), *flags,
                    '-o', str(root/'reader')], check=True)
    def check(name, accepted=False, identifier='fixture-v1'):
        result = subprocess.run([str(root/'reader'), identifier], capture_output=True, text=True)
        checks[name] = result.returncode == (0 if accepted else 1)
        assert checks[name], (name, result)
    shutil.copyfile(base/'fixture-v1.ini', profile)
    check('root_regular_profile', True)
    check('path_traversal_refused', identifier='../fixture-v1')
    check('missing_profile_refused', identifier='absent')
    profile.chmod(0o666)
    check('writable_profile_refused')
    profile.chmod(0o644)
    os.chown(profile, 1000, -1)
    check('nonroot_profile_refused')
    os.chown(profile, 0, -1)
    directory.chmod(0o777)
    check('writable_parent_refused')
    directory.chmod(0o755)
    target = directory/'target'
    profile.rename(target)
    profile.symlink_to(target)
    check('symlink_file_refused')
    profile.unlink()
    target.rename(profile)
    directory.rename(root/'actual')
    directory.symlink_to(root/'actual')
    check('symlink_directory_refused')
    directory.unlink()
    (root/'actual').rename(directory)
    profile.write_bytes(b'\x00hidden')
    check('embedded_nul_refused')
    profile.write_bytes(b'a'*8193)
    check('oversize_refused')
finally:
    shutil.rmtree(root)
    (base/'results').mkdir(exist_ok=True)
    (base/'results/profile-checks.json').write_text(json.dumps(checks, indent=2)+'\n')
print(json.dumps(checks))
