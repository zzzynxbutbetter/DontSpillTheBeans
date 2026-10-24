"""Masters the Don't Spill the Beans sound assets and writes the sound script for them.

    python scripts/master-audio.py              master assets/DontSpillTheBeans/*.wav into the mod
    python scripts/master-audio.py --measure    only print the loudness of the sources and of the reference mod
    python scripts/master-audio.py --ref <dir>  measure the reference mod's clips from <dir> too (default: the installed
                                                Dynamic Gear Rattling, Workshop 3808152720)

Needs ffmpeg/ffprobe on PATH, numpy and soundfile.

Loudness model. The game plays a clip at   file loudness + clip `volume` (script) + the volume the Lua passes.
The files are therefore mastered to one comfortable level (as loud as their peaks allow, up to FILE_LUFS) and the
loudness each sound should have *in the game* is reached with the per-clip `volume` in the sound script. The reference is
Dynamic Gear Rattling (its files carry volumes of 0.11 to 0.3 in its script, so file loudness alone says nothing).
REF_LUFS is what its default rattles measure in the game at full volume, see `--measure`:
    backpack rustle -35.5, clothes rustle -42.4, attached items -39.5 (at 3+ items)   -> mean about -39
Burn and foam are matched to REF_LUFS exactly, the emptying loops sit EMPTY_BELOW_REF dB under it; the walk sounds sit WALK_BELOW_REF dB under it at their
loudest (full of spilled contents, running), because they are meant to be heard *inside* the bag.
"""
import argparse, glob, json, math, os, re, subprocess, sys, tempfile
import numpy as np
import soundfile as sf

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
SRC = os.path.join(ROOT, 'assets', 'DontSpillTheBeans')
MOD = os.path.join(ROOT, 'mods', 'DontSpillTheBeans', '42', 'media')
OUT_SOUND = os.path.join(MOD, 'sound', 'DontSpillTheBeans')
OUT_SCRIPT = os.path.join(MOD, 'scripts', 'DontSpillTheBeans', 'DSTB_Sounds.txt')
DGR = 'W:/SteamLibrary/steamapps/workshop/content/108600/3808152720/mods/DynamicGearRattling/42/media'

REF_LUFS = -39.0          # in-game loudness of Dynamic Gear Rattling's default rattles at full volume
WALK_BELOW_REF = 4.0      # dB: the loudest the walk sounds get, relative to REF_LUFS
EMPTY_BELOW_REF = 2.0     # dB: the emptying loops sit this far under REF_LUFS
FILE_LUFS = -23.0         # level the files are mastered to when their peaks allow it
PEAK_CEILING = -1.0       # dBTP
MUFFLE_HZ = 600           # low-pass (two 2-pole filters) of the variants played when the character hears badly (hard of hearing)
MUFFLE_BELOW = 3.0        # dB: those variants are this much quieter than the normal sound, not the 11 dB the filter alone would take off

# group -> (sound name, source name pattern, kind, tail seconds kept after the last audible sample); a 'loop' sound is
# turned into a seamless loop (see make_loop) and played with `loop = true`: the game loops it until the action ends
GROUPS = [
    ('Burn',        r'burn(\d+)\.wav',            'event', 0.15),
    ('DryWalk',     r'dry_walk(\d+)-1\.wav',      'walk',  0.03),
    ('LiquidWalk',  r'liquid_walk(\d+)\.wav',     'walk',  0.03),
    ('WetWalk',     r'wet_walk(\d+)-1\.wav',      'walk',  0.03),
    ('EmptyBase',   r'empty_base\.wav',           'loop',  0.0),
    ('EmptyDry',    r'empty_dry\.wav',            'loop',  0.0),
    ('EmptyLiquid', r'empty_liquid\.wav',         'loop',  0.0),
    ('EmptyWet',    r'empty_wet\.wav',            'loop',  0.0),
    ('FoamOver',    r'foam_over\.wav',            'event', 0.25),
]
TRIM_DB = -48.0           # silence = this far under the clip's own peak (and never above -70 dBFS)


def ffmpeg(*args):
    return subprocess.run(['ffmpeg', '-hide_banner', '-nostats', '-y', *args], capture_output=True, text=True)


def loudness(data, sr):
    """(integrated LUFS, true peak dBTP) of a clip. Short clips are tiled to 3 s first: BS.1770 gates 400 ms blocks, which
    would throw a 0.3 s footstep away."""
    n = max(1, math.ceil(3.0 * sr / len(data)))
    with tempfile.TemporaryDirectory() as tmp:
        p = os.path.join(tmp, 'm.wav')
        sf.write(p, np.tile(data, (n, 1)), sr, subtype='FLOAT')
        err = ffmpeg('-i', p, '-af', 'ebur128=peak=true', '-f', 'null', '-').stderr
    tail = err[err.rfind('Summary:'):]
    i = re.search(r'I:\s+(-?[\d.]+) LUFS', tail)
    tp = re.search(r'Peak:\s+(-?[\d.]+) dBFS', tail)
    return (float(i.group(1)) if i else -99.0), (float(tp.group(1)) if tp else -99.0)


def trim(data, sr, tail):
    amp = np.abs(data).max(axis=1)
    peak = amp.max()
    floor = max(peak * 10 ** (TRIM_DB / 20), 10 ** (-70 / 20))
    idx = np.nonzero(amp >= floor)[0]
    a = max(0, idx[0] - int(0.003 * sr))
    b = min(len(data), idx[-1] + int(tail * sr))
    out = data[a:b].copy()
    fin, fout = int(0.002 * sr), int(min(tail, 0.12) * sr)
    out[:fin] *= np.linspace(0, 1, fin)[:, None]
    out[-fout:] *= np.linspace(1, 0, fout)[:, None]
    return out


LOOP_XFADE = 0.25         # s: the loop's seam is a crossfade this long
LOOP_MIN = 3.0            # s: shortest loop body worth taking from a clip


def _features(m, sr, ends):
    """Per candidate point (a sample index): band energies in dB and the level of the 0.25 s window that ends there."""
    w = int(LOOP_XFADE * sr)
    win = np.hanning(w)
    freqs = np.fft.rfftfreq(w, 1 / sr)
    edges = np.geomspace(100, 9000, 13)
    masks = [(freqs >= lo) & (freqs < hi) for lo, hi in zip(edges[:-1], edges[1:])]
    out = []
    for e in ends:
        seg = m[e - w:e]
        spec = np.abs(np.fft.rfft(seg * win)) ** 2
        out.append((np.array([10 * np.log10(spec[k].sum() + 1e-14) for k in masks]), 10 * np.log10((seg ** 2).mean() + 1e-14)))
    return out


def make_loop(data, sr):
    """A seamless loop out of a clip: picks the stretch [a, b) whose two ends match best (same level and spectrum, not a lull),
    and replaces the last LOOP_XFADE of it with a crossfade into the material just before `a`, so that playing it round and
    round continues exactly as the clip does at `a`. Returns (body, info)."""
    n, w = len(data), int(LOOP_XFADE * sr)
    m = data.mean(axis=1)
    step = int(0.05 * sr)
    ends = list(range(w, n + 1, step))
    feats = _features(m, sr, ends)
    median = float(np.median([f[1] for f in feats]))
    quiet = [max(0.0, (median - 6.0) - f[1]) for f in feats]
    min_len = min(LOOP_MIN, 0.5 * n / sr)
    best = None
    for i in range(len(ends)):
        for j in range(i + 1, len(ends)):
            length = (ends[j] - ends[i]) / sr
            if length < min_len:
                continue
            bands = float(np.abs(feats[i][0] - feats[j][0]).mean())
            level = abs(feats[i][1] - feats[j][1])
            score = bands + level + 0.5 * (quiet[i] + quiet[j]) - 0.4 * min(length, 6.0)
            if best is None or score < best[0]:
                best = (score, i, j, bands, level)
    score, i, j, bands, level = best
    a, b = ends[i], ends[j]
    body = data[a:b].copy()
    t = np.linspace(0, 1, w)[:, None]
    body[-w:] = data[b - w:b] * np.cos(t * np.pi / 2) + data[a - w:a] * np.sin(t * np.pi / 2)   # equal power
    info = dict(a=a / sr, b=b / sr, length=(b - a) / sr, bands=bands, level=level, score=score)
    return body, info


def lowpass_loop(data, sr):
    """The same low-pass, applied round the loop so the seam stays seamless: filter three copies, keep the middle one."""
    return lowpass(np.tile(data, (3, 1)), sr)[len(data):2 * len(data)]


def lowpass(data, sr):
    with tempfile.TemporaryDirectory() as tmp:
        a, b = os.path.join(tmp, 'a.wav'), os.path.join(tmp, 'b.wav')
        sf.write(a, data, sr, subtype='FLOAT')
        ffmpeg('-i', a, '-af', f'lowpass=f={MUFFLE_HZ}:poles=2,lowpass=f={MUFFLE_HZ}:poles=2', '-c:a', 'pcm_f32le', b)
        out, _ = sf.read(b, always_2d=True)
    return out[:len(data)]


def encode(data, sr, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        p = os.path.join(tmp, 'e.wav')
        sf.write(p, data, sr, subtype='FLOAT')
        r = ffmpeg('-i', p, '-c:a', 'libvorbis', '-q:a', '5', path)
        if r.returncode:
            raise RuntimeError(r.stderr[-400:])


def measure_dir(pattern, label):
    rows = {}
    for p in sorted(glob.glob(pattern)):
        d, sr = sf.read(p, always_2d=True)
        rows[os.path.basename(p)] = loudness(d, sr)
    return rows


def measure_ref(ref):
    scripts = {'ClothesRustle': 0.11, 'LightRustle': 0.25, 'AttachedItemRattle': 0.3, 'BackpackRustle': 0.3}
    print('Reference mod (file loudness looped, + script volume = in-game level at Lua volume 1):')
    levels = {}
    for g, vol in scripts.items():
        import soundfile  # noqa
        files = sorted(glob.glob(f'{ref}/sound/DynamicGearRattling/{g}[0-9]*.ogg'))
        ls = []
        for f in files:
            d, sr = sf.read(f, always_2d=True)
            ls.append(loudness(d, sr)[0])
        mean = 10 * math.log10(np.mean([10 ** (l / 10) for l in ls]))
        levels[g] = mean + 20 * math.log10(vol)
        print(f'  {g:20s} {len(files):2d} clips  files {mean:6.1f} LUFS  x{vol}  -> {levels[g]:6.1f} LUFS')
    return levels


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--measure', action='store_true')
    ap.add_argument('--ref', default=DGR)
    args = ap.parse_args()

    if os.path.isdir(args.ref):
        measure_ref(args.ref)
    if args.measure:
        for name, (i, tp) in measure_dir(os.path.join(SRC, '*.wav'), 'src').items():
            print(f'  {name:22s} I={i:6.1f}  TP={tp:6.1f}')
        return

    blocks, report, loops = [], [], {}
    for sound, pattern, kind, tail in GROUPS:
        files = sorted((f for f in os.listdir(SRC) if re.fullmatch(pattern, f)),
                       key=lambda f: [int(x) for x in re.findall(r'\d+', f)] or [0])
        if not files:
            print(f'!! no source for {sound}')
            continue
        goal = REF_LUFS - {'walk': WALK_BELOW_REF, 'loop': EMPTY_BELOW_REF}.get(kind, 0.0)   # loudness wanted in the game at volume 1
        for variant in ('', 'M'):
            lines = []
            for n, f in enumerate(files, 1):
                data, sr = sf.read(os.path.join(SRC, f), always_2d=True)
                if kind == 'loop':
                    data, info = make_loop(data, sr)
                    if not variant:
                        print(f'loop {f}: {info["a"]:.2f}-{info["b"]:.2f} s ({info["length"]:.2f} s), ends differ by {info["bands"]:.1f} dB (bands) / {info["level"]:.1f} dB (level)')
                    if variant:
                        data = lowpass_loop(data, sr)
                else:
                    data = trim(data, sr, tail)
                    if variant:
                        data = lowpass(data, sr)
                i0, tp0 = loudness(data, sr)
                # The file level: FILE_LUFS, or as loud as the peak ceiling allows.
                file_lufs = min(FILE_LUFS, i0 + (PEAK_CEILING - tp0))
                data = data * 10 ** ((file_lufs - i0) / 20)
                vol = 10 ** ((goal - (MUFFLE_BELOW if variant else 0.0) - file_lufs) / 20)
                if vol > 1:
                    print(f'!! {f}: needs volume {vol:.2f}, clamped')
                    vol = 1.0
                name = f'{sound}{variant}{n}.ogg' if len(files) > 1 else f'{sound}{variant}.ogg'
                encode(data, sr, os.path.join(OUT_SOUND, name))
                lines.append((name, round(vol, 4)))
                loops[f'DSTB_{sound}{variant}'] = kind == 'loop'
                if not variant:
                    report.append((sound, f, len(data) / sr, i0, tp0, file_lufs, vol))
            blocks.append((f'DSTB_{sound}{variant}', lines))

    os.makedirs(os.path.dirname(OUT_SCRIPT), exist_ok=True)
    with open(OUT_SCRIPT, 'w', encoding='utf8', newline='\n') as out:
        # Only /* */ comments are understood by the script parser; anything else breaks the whole file.
        out.write('/* Generated by scripts/master-audio.py from assets/DontSpillTheBeans: do not edit by hand.\n')
        out.write('   Clip volumes put every sound at its target loudness in the game; the "M" sounds are the muffled variants. */\n')
        out.write('module DontSpillTheBeans\n{\n')
        for name, lines in blocks:
            out.write(f'    sound {name}\n    {{\n        category = Item,\n        is3D = true,\n')
            if loops.get(name):
                out.write('        loop = true,\n')
            out.write('\n')
            for f, v in lines:
                out.write(f'        clip {{file = media/sound/DontSpillTheBeans/{f}, volume = {v}, distanceMin = 3, distanceMax = 8, reverbFactor = 1,}}\n')
            out.write('    }\n\n')
        out.write('}\n')

    print(f'{"sound":12s} {"source":18s} {"len":>5s} {"I src":>7s} {"TP src":>7s} {"file":>7s} {"volume":>7s}')
    for s, f, d, i0, tp0, fl, v in report:
        print(f'{s:12s} {f:18s} {d:5.2f} {i0:7.1f} {tp0:7.1f} {fl:7.1f} {v:7.3f}')


if __name__ == '__main__':
    main()
