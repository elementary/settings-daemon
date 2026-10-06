#!/usr/bin/env python3
"""Render the five-band profile layout with native SPA filters."""
import array
import configparser
import itertools
import json
import math
import os
from pathlib import Path
import subprocess
import tempfile

assert os.environ.get('EQ_PRIVATE_TEST') == '1' and not Path('/dev/snd').exists()
base = Path(__file__).resolve().parent
profile = configparser.ConfigParser()
profile.read(base.parent/'data/generic-speakers-v1.ini')
p = profile['Profile']
def values(key):
    return [float(value) for value in p[key].split(';') if value]
types = [value for value in p['Types'].split(';') if value]
frequencies, qs = values('Frequencies'), values('Q')
minimum, maximum = values('MinimumGains'), values('MaximumGains')
assert p['Node'] == '*' and not values('DefaultGains')
rules = json.loads((base.parent/'data/50-elementary-speaker-equalizer.conf').read_text())
assert 'node.filter-graph.rules' not in rules
labels = {'low-shelf': 'bq_lowshelf', 'peak': 'bq_peaking', 'high-shelf': 'bq_highshelf'}
graph = dict(nodes=[dict(type='builtin', name=f'eos_eq_{i+1}', label=labels[kind],
    control=dict(Freq=frequency, Q=q, Gain=0.))
    for i, (kind, frequency, q) in enumerate(zip(types, frequencies, qs))],
    links=[dict(output=f'eos_eq_{i}:Out', input=f'eos_eq_{i+1}:In') for i in range(1,5)])
graph['nodes'].append(dict(type='builtin', name='eos_eq_h', label='linear',
    control=dict(Mult=1., Add=0., Control=0.)))
graph['links'].append(dict(output='eos_eq_5:Out', input='eos_eq_h:In'))

# Reuse the native SPA fixture; no reimplementation of its DSP arithmetic.
peaks, transient_overshoots, rendered = [], 0, 0
with tempfile.TemporaryDirectory(prefix='generic-eq-pcm-') as work:
    case = Path(work)/'graph.json'
    def render(rate, gains, multiplier, mono, measure=True):
        global rendered, transient_overshoots
        for node, gain in zip(graph['nodes'], gains):
            node['control']['Gain'] = gain
        graph['nodes'][-1]['control']['Mult'] = multiplier
        case.write_text(json.dumps(graph))
        samples = array.array('f')
        for value in mono:
            samples.extend((value, -value*.5))
        result = subprocess.run([str(base/'render-graph'), str(case), str(rate)],
            input=samples.tobytes(), capture_output=True, timeout=10)
        assert result.returncode == 0, result.stderr
        output = array.array('f')
        output.frombytes(result.stdout)
        assert len(output) == len(samples) and all(math.isfinite(v) for v in output)
        assert max(abs(r+l*.5) for l, r in zip(output[::2], output[1::2])) < 1e-6
        rendered += 1
        if measure:
            peak = max(abs(value) for value in output)
            transient_overshoots += peak > 1
            peaks.append(peak)
        return output[::2]

    for rate in (32000, 48000, 192000):
        impulse = array.array('f', [1]+[0]*(rate//4-1))
        for gains in itertools.product(*zip(minimum, maximum)):
            h = render(rate, gains, 1., impulse, False)
            adversarial = array.array('f', [1 if v >= 0 else -1 for v in reversed(h)])
            render(rate, gains, 1.0, adversarial)
        for gains in ([0]*5, [-6,0,0,0,0], [0,0,-6,0,0], maximum):
            multiplier = 1.0
            if not any(gains):
                assert multiplier == 1
            h = render(rate, gains, 1., impulse, False)
            adversarial = array.array('f', [1 if v >= 0 else -1 for v in reversed(h)])
            render(rate, gains, multiplier, adversarial)
            for frequency in frequencies:
                sine = array.array('f', [.5*math.sin(2*math.pi*frequency*i/rate) for i in range(rate//4)])
                output = render(rate, gains, multiplier, sine)
                if not any(gains):
                    assert output == sine
print(json.dumps(dict(finite_native_cases=rendered,
    largest_native_pcm_peak=max(peaks),
    full_scale_transient_overshoots=transient_overshoots)))
