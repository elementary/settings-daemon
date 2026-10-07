#!/usr/bin/env python3
"""Production AEC startup with delayed Pulse endpoint visibility, in a private SDK.
Uses the companion harness's private PW/Pulse/WP stack and ALSA null fixtures.
"""
import os
from pathlib import Path
import queue
import subprocess
import tempfile
import threading
import time

assert os.environ.get('AEC_PRIVATE_TEST') == '1'
assert not Path('/dev/snd').exists()
BUILD = Path(__file__).resolve().parent / 'build'


def scenario(delay, restored):
    with tempfile.TemporaryDirectory(prefix='runtime-', dir=BUILD) as directory:
        root = Path(directory)
        root.chmod(0o700)
        env = dict(os.environ, XDG_RUNTIME_DIR=str(root), XDG_CONFIG_HOME=str(root / 'config'),
                   XDG_STATE_HOME=str(root / 'state'), XDG_CACHE_HOME=str(root / 'cache'),
                   PULSE_SERVER='unix:' + str(root / 'native'), PIPEWIRE_RUNTIME_DIR=str(root),
                   PIPEWIRE_REMOTE='pipewire-0', GSETTINGS_BACKEND='memory',
                   GSETTINGS_SCHEMA_DIR=str(BUILD / 'schemas'), ALSA_CONFIG_PATH=str(root / 'asound.conf'))
        for key in ('DBUS_SESSION_BUS_ADDRESS', 'DISPLAY', 'WAYLAND_DISPLAY', 'LD_PRELOAD',
                    'PIPEWIRE_CONFIG_PREFIX', 'PIPEWIRE_CONFIG_NAME', 'PIPEWIRE_CORE'):
            env.pop(key, None)
        (root / 'asound.conf').write_text('pcm.!default { type null }\n')
        config = root / 'pipewire'
        (config / 'pipewire.conf.d').mkdir(parents=True)
        env['PIPEWIRE_CONFIG_DIR'] = str(config)
        for name in ('pipewire.conf', 'client.conf', 'pipewire-pulse.conf'):
            text = (Path('/usr/share/pipewire') / name).read_text()
            (config / name).write_text(text.replace('unix:native', 'unix:' + str(root / 'native')))
        objects = []
        for direction, media, name in (('sink', 'Sink', 'physical_output'), ('source', 'Source', 'physical_input')):
            objects.append('''{ factory = adapter args = {
                factory.name = api.alsa.pcm.%s node.name = %s node.description = %s
                media.class = Audio/%s device.api = alsa device.class = sound api.alsa.path = default
                api.alsa.period-size = 480 api.alsa.headroom = 0 api.alsa.disable-mmap = true
                audio.rate = 48000 audio.channels = 2 audio.position = [ FL FR ]
            } }''' % (direction, name, name, media))
        (config / 'pipewire.conf.d/10-fixtures.conf').write_text('context.objects = [\n' + '\n'.join(objects) + '\n]\n')
        processes, logs = [], []

        def start(name, args, **kwargs):
            log = open(root / (name + '.log'), 'w')
            logs.append(log)
            process = subprocess.Popen(args, env=kwargs.pop('env', env), stderr=log,
                                       stdout=kwargs.pop('stdout', log), **kwargs)
            processes.append(process)
            return process

        def pactl(*args, check=True):
            return subprocess.run(['pactl', *args], env=env, capture_output=True, text=True,
                                  check=check, timeout=8).stdout.strip()

        def eventually(fn, limit=10):
            end = time.monotonic() + limit
            while time.monotonic() < end:
                result = fn()
                if result:
                    return result
                time.sleep(.03)
            raise AssertionError('Timed out: ' + repr(fn))

        samples = queue.Queue()
        last = None

        def status(predicate, limit=10):
            nonlocal last
            end = time.monotonic() + limit
            while time.monotonic() < end:
                try:
                    last = samples.get(timeout=.2)
                except queue.Empty:
                    continue
                if predicate(last):
                    return last
            raise AssertionError('AEC status timeout: ' + repr(last))

        def owned():
            return [line for line in pactl('list', 'short', 'modules').splitlines()
                    if '\tmodule-echo-cancel\t' in line and 'device.echo_cancel.owner=io.elementary.settings.sound' in line]

        try:
            bus = start('bus', ['dbus-daemon', '--session', '--nofork', '--print-address=1'],
                        stdout=subprocess.PIPE, text=True)
            env['DBUS_SESSION_BUS_ADDRESS'] = bus.stdout.readline().strip()
            assert env['DBUS_SESSION_BUS_ADDRESS']
            start('pipewire', ['pipewire'])
            eventually(lambda: (root / 'pipewire-0').exists())
            start('pulse', ['pipewire-pulse'])
            start('wireplumber', ['wireplumber'])
            eventually(lambda: 'physical_input' in pactl('list', 'short', 'sources', check=False))
            eventually(lambda: 'physical_output' in pactl('list', 'short', 'sinks', check=False))
            pactl('set-default-source', 'physical_input')
            pactl('set-default-sink', 'physical_output')
            delay_file = root / 'delay'
            delay_file.write_text(str(delay))
            owner_env = dict(env, LD_PRELOAD=str(BUILD / 'endpoint-delay.so'), AEC_TEST_DELAY_FILE=str(delay_file))
            owner = start('owner', [str(BUILD / 'owner'), 'restore' if restored else 'explicit'],
                          env=owner_env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)

            def read():
                for line in owner.stdout:
                    samples.put(line.strip().split(' ', 4))
            threading.Thread(target=read, daemon=True).start()
            if not restored:
                status(lambda s: s[1:3] == ['true', 'false'])
                owner.stdin.write('enable\n')
                owner.stdin.flush()
            eventually(lambda: 'AEC_TEST_LOAD' in (root / 'owner.log').read_text())
            eventually(owned)
            # Supply endpoint subscription events after the visibility gap.
            # Repeated mute notifications also exercise the bounded failure latch.
            start_time = time.monotonic()
            while time.monotonic() - start_time < 3.5:
                if owned():
                    pactl('set-sink-mute', 'elementary_echo_cancel_sink', 'toggle')
                time.sleep(.1)
            if delay < 2000:
                status(lambda s: s[:5] == ['true', 'true', 'false', 'true', '-'])
                assert len(owned()) == 1
                assert (root / 'owner.log').read_text().count('AEC_TEST_LOAD') == 1
                info = pactl('info')
                assert 'Default Source: elementary_echo_cancel_source' in info
                assert 'Default Sink: elementary_echo_cancel_sink' in info
            else:
                state = status(lambda s: s[0] == 'false' and s[2] == 'false' and s[4] != '-')
                assert state[3] == ('true' if restored else 'false'), state
                assert not owned()
                # Continue external notifications past the timeout; no new load.
                for _ in range(12):
                    pactl('set-sink-mute', 'physical_output', 'toggle')
                    time.sleep(.1)
                assert (root / 'owner.log').read_text().count('AEC_TEST_LOAD') == 1
                delay_file.write_text('0')
                owner.stdin.write('disable\n')
                owner.stdin.flush()
                status(lambda s: s[2:4] == ['false', 'false'])
                owner.stdin.write('enable\n')
                owner.stdin.flush()
                status(lambda s: s[:5] == ['true', 'true', 'false', 'true', '-'])
                assert len(owned()) == 1
            print('PASS', 'restore' if restored else 'explicit', 'endpoint gap', delay, flush=True)
        except Exception:
            for path in root.glob('*.log'):
                print(path.name, path.read_text())
            raise
        finally:
            for process in reversed(processes):
                if process.poll() is None:
                    process.terminate()
            for process in reversed(processes):
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            for log in logs:
                log.close()


scenario(600, True)
scenario(6000, True)
scenario(6000, False)
