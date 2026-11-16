import math, random, struct, wave, sys, os, subprocess

# Writes the backing tracks for the clip editor into Resources/Music, made from plain waveforms.
SR = 22050

def midi(n):
    return 440 * 2 ** ((n - 69) / 12)

def osc(kind, cycles):
    x = cycles % 1.0
    if kind == 'sine':
        return math.sin(2 * math.pi * x)
    if kind == 'square':
        return 0.7 if x < 0.5 else -0.7
    if kind == 'saw':
        return 2 * x - 1
    return 4 * abs(x - 0.5) - 1

def make(name, bpm, chords, lead, snare, hats, lead_decay):
    beat = 60 / bpm
    bars = 8
    n = int(SR * beat * 4 * bars)
    rnd = random.Random(11)
    out = [0.0] * n
    sixteenth = beat / 4
    for i in range(n):
        t = i / SR
        bar = int(t / (beat * 4))
        chord = chords[(bar // 2) % len(chords)]
        s16 = int(t / sixteenth)
        ts = t - s16 * sixteenth
        note = chord[s16 % len(chord)] + 12
        v = 0.2 * osc(lead, midi(note) * t) * math.exp(-ts * lead_decay) * min(1, ts * 300)
        half = beat / 2
        b = int(t / half)
        tb = t - b * half
        v += 0.32 * osc('triangle', midi(chord[0] - 12) * t) * math.exp(-tb * 3.5) * min(1, tb * 300)
        bt = int(t / beat)
        tk = t - bt * beat
        v += 0.6 * math.sin(2 * math.pi * 52 * tk + 7 * (1 - math.exp(-tk * 30))) * math.exp(-tk * 9)
        if hats and s16 % 2 == 1:
            v += hats * (rnd.random() * 2 - 1) * math.exp(-ts * 80)
        if snare and bt % 2 == 1:
            v += snare * (rnd.random() * 2 - 1) * math.exp(-tk * 16)
        out[i] = v
    peak = max(abs(x) for x in out) or 1
    path = '/tmp/music-%s.wav' % name
    with wave.open(path, 'wb') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(b''.join(struct.pack('<h', int(x / peak * 0.8 * 32767)) for x in out))
    target = os.path.join(sys.argv[1], 'music-%s.m4a' % name)
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', path, '-c:a', 'aac', '-b:a', '96k', target], check=True)

make('arcade', 124, [[60, 64, 67, 72], [57, 60, 64, 69], [53, 57, 60, 65], [55, 59, 62, 67]], 'square', 0.25, 0.1, 10)
make('chill', 86, [[62, 65, 69, 72], [55, 59, 62, 65], [60, 64, 67, 71], [57, 60, 64, 67]], 'sine', 0, 0.05, 5)
make('hype', 136, [[57, 60, 64, 69], [53, 57, 60, 65], [60, 64, 67, 72], [55, 59, 62, 67]], 'saw', 0.35, 0.14, 12)
make('bounce', 112, [[55, 59, 62, 67], [52, 55, 59, 64], [48, 52, 55, 60], [50, 54, 57, 62]], 'triangle', 0.3, 0.1, 8)
