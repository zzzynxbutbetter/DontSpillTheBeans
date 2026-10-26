"""Builds containers-<Key>.html: a markup tool for deciding how each fluid container and each bag of a source behaves.

    python docs/DontSpillTheBeans/tools/food-rules/build_containers.py [Key ...]    (no key = Vanilla + every mod)

Fluid containers (items with a FluidContainer component): Open (spills whenever it holds something), Sealed (never
spills), or Sealed when full (sealed until anything has been used/poured out). Items that have an opening recipe (their own,
or one that Don't Spill the Beans: Vessel Fixes adds) ignore these marks: they are sealed until opened and then spill even
while full; the page shows an "opens first" tag for them. Bags (container items): whether they
shield liquids carried inside them (like a plastic bag or lunchbox). The page pre-computes what the mod does today for
each item ("current") so only the exceptions need changing. "Save progress file" writes a json that
export-containers.py turns into DSTB_Compat_<Key>_Containers.lua.
"""
import base64, glob, importlib.util, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
spec = importlib.util.spec_from_file_location('foodbuild', os.path.join(HERE, 'build.py'))
fb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fb)
from packread import read_pack  # noqa: E402

GAME = 'W:/GameModding/ProjectZomboid/reference/game-media/'
SOURCES = dict(fb.MODS)
SOURCES['Vanilla'] = dict(
    title='Project Zomboid (vanilla)', workshop='vanilla',
    scripts=[GAME + 'scripts/generated/items/*.txt'],
    textures=[GAME + 'textures'],
    names=[GAME + 'lua/shared/Translate/EN/ItemName.json'],
    packs=[GAME + 'texturepacks/UI.pack', GAME + 'texturepacks/UI2.pack'])
# Sapph's Cooking's own fluid items also live in its script folders other than items/ - the glob already covers them.


def current_rules():
    """What DSTB_Config.lua does today, parsed from the file."""
    s = open(fb.CONFIG, encoding='utf8').read()
    block = re.search(r'OpenContainerNames = \{(.*?)\n    \},', s, re.S).group(1)
    open_names = {a or b for a, b in re.findall(r'(?:\["([^"]+)"\]|(\w+)) = true', block)}
    prot = set(fb.compat_rules('DSTB_Compat_Vanilla_Containers.lua', 'protective'))
    whenfull = set(fb.compat_rules('DSTB_Compat_Vanilla_Containers.lua', 'whenfull'))
    return open_names, prot, whenfull


REPO = os.path.abspath(os.path.join(HERE, '..', '..', '..', '..'))


def vessel_fixes():
    """Item ids that Don't Spill the Beans: Vessel Fixes (the core mod and its add-ons, mods/DontSpillTheBeansVesselFixes*) give
    an opening recipe and a sealed state: id -> recipe. Such an item is sealed until opened and spills once opened even while
    full, so a "sealed when full" mark means nothing for it while the add-on is installed."""
    out = {}
    for f in glob.glob(os.path.join(REPO, 'mods', 'DontSpillTheBeansVesselFixes*', '42', 'media', 'scripts', '*_items.txt')):
        t = open(f, encoding='utf8').read()
        module = re.search(r'module\s+(\w+)', t).group(1)
        for m in re.finditer(r'\n\s*item\s+(\w+)\s*\{(.*?)\n    \}', t, re.S):
            recipe = re.search(r'OpeningRecipe\s*=\s*(\w+)', m.group(2))
            if recipe:
                out[module + '.' + m.group(1)] = recipe.group(1)
    return out


FIZZ_FLUID = re.compile(r'^(Cola|ColaDiet|GingerAle|Soda\w*|Beer|Champagne|Cider|Tonic\w*|Seltzer|Sparkling\w*|Energy\w*|Brawndo)$', re.I)
FIZZ_NAME = re.compile(r'\b(cola|soda|pop|beer|champagne|lager|ale|cider|tonic|seltzer|sparkling|fizzy|carbonated|energy drink|brawndo|sprite|pepsi|root beer)\b', re.I)


def suggest_fizzy(display, fluids):
    """A guess only (the page makes you confirm): fluids that are fizzy drinks, or a name that says so. Needs a default fluid."""
    if not fluids:
        return False
    if any(FIZZ_FLUID.match(f) for f in fluids):
        return True
    if 'CarbonatedWater' in fluids and 'Water' not in fluids:
        return True
    return bool(FIZZ_NAME.search(display))


def body_info(body):
    cn = re.search(r'ContainerName\s*=\s*([\w ]+?)\s*,', body)
    cap = re.search(r'Capacity\s*=\s*([\d.]+)', re.sub(r'component\s+\w+', lambda m: m.group(0), body))
    fluids = re.findall(r'fluid\s*=\s*([\w]+):', body)
    return (cn.group(1).strip() if cn else ''), (cap.group(1) if cap else ''), sorted(set(fluids))


def build(key):
    cfg = SOURCES[key]
    files = sorted({f for g in cfg['scripts'] for f in glob.glob(g, recursive=True)})
    # parse with bodies
    items = {}
    for f in files:
        t = open(f, encoding='utf8', errors='ignore').read()
        mod = re.search(r'module\s+(\w+)', t)
        mod = mod.group(1) if mod else 'Base'
        for m in re.finditer(r'\n\s*item\s+(\w+)\s*\{', t):
            i, depth = m.end(), 1
            while depth and i < len(t):
                depth += (t[i] == '{') - (t[i] == '}')
                i += 1
            body = t[m.end():i - 1]
            props = {}
            for pm in re.finditer(r'^\s*([A-Za-z]+)\s*=\s*([^,\n]+),?', body, re.M):
                props.setdefault(pm.group(1), pm.group(2).strip())
            items[mod + '.' + m.group(1)] = {'props': props, 'body': body, 'file': os.path.basename(f)}
    names = fb.read_names(cfg['names'])
    open_names, prot, whenfull = current_rules()
    prot = prot | set(cfg.get('seed_protective', []))   # optional: rules to show as current before they are exported
    seed_fizzy = set(cfg.get('seed_fizzy', []))
    vf = vessel_fixes()

    textures = {}
    for d in cfg['textures']:
        for f in glob.glob(d + '/*.png'):
            textures.setdefault(os.path.basename(f).lower(), f)
    packed = {}
    for pk in cfg.get('packs', []) + [p for p in fb.VANILLA_PACKS if p not in cfg.get('packs', [])]:
        try:
            packed.update(fb.item_sprites(pk))
        except Exception as e:  # noqa: BLE001
            print('  (could not read', os.path.basename(pk), '-', e, ')')

    icons, rows = {}, []
    for full, v in items.items():
        p, body = v['props'], v['body']
        is_fluid = 'component FluidContainer' in body
        is_bag = 'base:container' in p.get('ItemType', '').lower()
        if not (is_fluid or is_bag):
            continue
        short = full.split('.', 1)[1]
        cname, cap, fluids = body_info(body) if is_fluid else ('', p.get('Capacity', ''), [])
        if is_fluid:
            kind = 'fluid'
            cur = 'whenfull' if full in whenfull else ('open' if cname in open_names else 'sealed')
        else:
            kind = 'bag'
            cur = 'protective' if full in prot else 'plain'
        icon = p.get('Icon') or (p.get('IconsForTexture', '').split(';')[0].strip() or None)   # tiered bags only list IconsForTexture
        if icon and icon not in icons:
            path = textures.get(('item_' + icon).lower() + '.png')
            if path:
                icons[icon] = 'data:image/png;base64,' + base64.b64encode(open(path, 'rb').read()).decode()
            elif ('item_' + icon).lower() in packed:
                icons[icon] = 'data:image/png;base64,' + base64.b64encode(packed[('item_' + icon).lower()]).decode()
            else:
                icons[icon] = None
        display = names.get(full) or p.get('DisplayName') or short
        rows.append({
            'id': full, 'name': display.replace('_', ' '), 'kind': kind, 'cname': cname, 'cap': cap, 'fluids': fluids,
            'sugg': bool(is_fluid and (full in seed_fizzy or suggest_fizzy(display, fluids))),
            'opens': (vf.get(full) or p.get('OpeningRecipe', '')) if is_fluid else '', 'vf': bool(is_fluid and full in vf),
            'cur': cur, 'icon': icon, 'cat': p.get('DisplayCategory', ''), 'wear': 'CanBeEquipped' in p or 'BodyLocation' in p,
            'file': re.sub(r'\.txt$', '', v['file']),
        })
    rows.sort(key=lambda r: (r['kind'], r['cname'], r['name'].lower()))
    icons = {k: v for k, v in icons.items() if v}
    modules = {}
    for r in rows:
        m = r['id'].split('.')[0]
        modules[m] = modules.get(m, 0) + 1
    strip = max(modules, key=modules.get) + '.' if modules else ''
    html = open(os.path.join(HERE, 'template-containers.html'), encoding='utf8').read()
    for a, b in (('__TITLE__', cfg['title']), ('__KEY__', 'dstb-containers-' + key), ('__STRIP__', strip),
                 ('__ROWS__', json.dumps(rows, separators=(',', ':'))), ('__ICONS__', json.dumps(icons, separators=(',', ':')))):
        html = html.replace(a, b)
    out = os.path.join(HERE, f'containers-{key}.html')
    open(out, 'w', encoding='utf8').write(html)
    nf = sum(1 for r in rows if r['kind'] == 'fluid')
    print(f"{key}: {nf} fluid containers, {len(rows) - nf} bags | {sum(1 for r in rows if r['icon'] not in icons)} without icon "
          f"| {round(os.path.getsize(out) / 1e6, 1)} MB -> {os.path.basename(out)}")


def main():
    for k in (sys.argv[1:] or list(SOURCES)):
        build(k)


if __name__ == '__main__':
    sys.exit(main())
