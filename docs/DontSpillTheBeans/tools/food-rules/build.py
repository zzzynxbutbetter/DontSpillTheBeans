"""Builds food-rules-<Key>.html: a markup tool for deciding which food-spill rule each food of a mod follows.

    python docs/DontSpillTheBeans/tools/food-rules/build.py [Key ...]     (no key = every mod below)

Reads the installed mod's item scripts + icons and the rules already in DSTB_Config.lua, and writes a self-contained
page next to this file (open it in a browser). Marks are kept in the browser; "Save progress file" writes a json that
export-lua.py turns into the mod's DSTB_Compat_<Key>.lua.
"""
import base64, glob, json, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..', '..', '..'))
CONFIG = os.path.join(REPO, 'mods/DontSpillTheBeans/42/media/lua/shared/DSTB_Config.lua')
W = 'W:/SteamLibrary/steamapps/workshop/content/108600/'

GAME = 'W:/GameModding/ProjectZomboid/reference/game-media/'

# Every source may use vanilla icons (overridden or reused items), so these packs are always searched after its own.
VANILLA_PACKS = [GAME + 'texturepacks/UI.pack', GAME + 'texturepacks/UI2.pack']
_PACK_CACHE = {}


def item_sprites(pack):
    """{lower-case sprite name: png bytes} of the Item_* sprites in a texture pack (read once)."""
    if pack not in _PACK_CACHE:
        from packread import read_pack
        _PACK_CACHE[pack] = {k.lower(): v for k, v in read_pack(pack, want=lambda n: n.startswith('Item_')).items()}
    return _PACK_CACHE[pack]

LTPE_MODS = [('', '42.20'), ('BDA', '42.20'), ('BSS', '42.20'), ('CB', '42.20'), ('HCB', '42.20'), ('HM', '42.20'), ('KW', '42.21'),
             ('TPT', '42.20'), ('VFX', '42.20')]

MODS = {
    # Vanilla: rows are editable (not locked to the rules already in DSTB_Config.lua); import the current-rules progress file to see them.
    'Vanilla': dict(
        title='Project Zomboid (vanilla)', workshop='vanilla', editable=True,
        scripts=[GAME + 'scripts/generated/items/*.txt'],
        textures=[GAME + 'textures'], packs=[GAME + 'texturepacks/UI.pack', GAME + 'texturepacks/UI2.pack'],
        names=[GAME + 'lua/shared/Translate/EN/ItemName.json']),
    'VFE': dict(
        title='Vanilla Foods Expanded', workshop='3577903007', storage='dstb-vfe-food-marks',
        scripts=[W + '3577903007/mods/Vanilla Foods Expanded/42.18/media/scripts/items/*.txt'],
        textures=[W + '3577903007/mods/Vanilla Foods Expanded/common/media/textures'],
        names=[W + '3577903007/mods/Vanilla Foods Expanded/42.18/media/lua/shared/Translate/EN/ItemName.json']),
    'Pomps': dict(
        title="Pomp's Items - Just the Food", workshop='2792348686',
        scripts=[W + '2792348686/mods/PompsItemsFood/42.0/media/scripts/**/*.txt'],
        textures=[W + '2792348686/mods/PompsItemsFood/common/media/textures', W + '2792348686/mods/PompsItemsFood/media/textures'],
        names=[W + '2792348686/mods/PompsItemsFood/common/media/lua/shared/Translate/EN/ItemName.json']),
    'Sapph': dict(
        title="Sapph's Cooking", workshop='3409143790',
        scripts=[W + '3409143790/mods/SapphCookingB42/42.20.0/media/scripts/**/*.txt'],
        textures=[W + '3409143790/mods/SapphCookingB42/42.20.0/media/textures'],
        names=[W + '3409143790/mods/SapphCookingB42/42.20.0/media/lua/shared/Translate/EN/ItemName.json']),
    # Authentic Z: its three variants (Current, Backpacks+, Lite) share item names under their own modules, so all three are read.
    'AuthZ': dict(
        title='Authentic Z', workshop='2335368829',
        scripts=[W + '2335368829/mods/Authentic Z - %s/42/media/scripts/**/*.txt' % v for v in ('Current', 'Backpacks+', 'Lite')],
        textures=[W + '2335368829/mods/Authentic Z - %s/%s/media/textures' % (v, d) for v in ('Current', 'Backpacks+', 'Lite') for d in ('42', 'common')],
        names=[W + '2335368829/mods/Authentic Z - %s/42/media/lua/shared/Translate/EN/ItemName.json' % v for v in ('Current', 'Backpacks+', 'Lite')]),
    # Long Term Preservation Extended: one Workshop item holding the main mod and eight DLC mods, each read at the newest
    # version folder the game would load (42.20; Knox Wildlife has 42.21). The 42.12 / 42.13 folders are legacy.
    'LTPE': dict(
        title='Long Term Preservation Extended', workshop='3597673472',
        scripts=[W + '3597673472/mods/LongTermPreservationExtended%s/%s/media/scripts/**/*.txt' % (s, v) for s, v in LTPE_MODS],
        textures=[W + '3597673472/mods/LongTermPreservationExtended%s/common/media/textures' % s for s, v in LTPE_MODS],
        names=[W + '3597673472/mods/LongTermPreservationExtended%s/common/media/lua/shared/Translate/EN/ItemName.json' % s for s, v in LTPE_MODS]),
    'MRE': dict(
        title='MRE Mod', workshop='3765409550',
        scripts=[W + '3765409550/mods/MRE Mod/42/media/scripts/**/*.txt'],
        textures=[W + '3765409550/mods/MRE Mod/42/media/textures'],
        names=[]),
}


def parse_items(files):
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
            items[mod + '.' + m.group(1)] = {'props': props, 'file': os.path.basename(f)}
    return items


def compat_rules(file, name):
    """Ids a generated compat module sets with rule("<name>", { ... })."""
    path = os.path.join(os.path.dirname(CONFIG), file)
    if not os.path.exists(path):
        return []
    s = open(path, encoding='utf8').read()
    return [i for m in re.finditer(r'rule\("%s", \{(.*?)\n\}\)' % name, s, re.S) for i in re.findall(r'"([^"]+)"', m.group(1))]


def sealed_jars():
    """Closed jars of DSTB_Compat_Reseal.lua (the values of its pairs): exempt by rule, like any closed jar."""
    path = os.path.join(os.path.dirname(CONFIG), 'DSTB_Compat_Reseal.lua')
    return set(re.findall(r'\] = "([^"]+)"', open(path, encoding='utf8').read())) if os.path.exists(path) else set()


def config_rules():
    """Food rules already in force from the vanilla compat module: {fullType: 'exempt' | 'whole'}."""
    rules = {}
    for name in ('exempt', 'whole'):
        for full in compat_rules('DSTB_Compat_Vanilla.lua', name):
            rules[full] = name
    return rules


LIQUID_NAME = re.compile(r'soup|stew|broth|chowder|bisque|porridge|gruel|chili|curry|milkshake|smoothie|gravy|sauce|juice|tea\b|coffee|cocoa|latte', re.I)


def open_vessels():
    """Items DSTB_Config.lua treats as open vessels (what a food leaves behind when used up)."""
    s = open(CONFIG, encoding='utf8').read()
    m = re.search(r'OpenFoodContainers = \{(.*?)\n    \},', s, re.S)   # the list is gone from the config: any ReplaceOnUse item is a vessel now
    return set(re.findall(r'\["([^"]+)"\] = true', m.group(1))) if m else set()


def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return 0.0


def read_names(paths):
    names = {}
    for p in paths:
        if os.path.exists(p):
            try:
                names.update({(k[9:] if k.startswith('ItemName_') else k): v for k, v in json.load(open(p, encoding='utf8')).items()})
            except ValueError:
                pass
    return names


def build(key):
    cfg = MODS[key]
    files = sorted({f for g in cfg['scripts'] for f in glob.glob(g, recursive=True)})
    items = parse_items(files)
    names = read_names(cfg['names'])
    rules = config_rules()
    jars = sealed_jars()
    vessels = open_vessels()
    textures = {}
    for d in cfg['textures']:
        for f in glob.glob(d + '/*.png'):
            textures.setdefault(os.path.basename(f).lower(), f)
    packed = {}
    for pk in cfg.get('packs', []) + [p for p in VANILLA_PACKS if p not in cfg.get('packs', [])]:
        packed.update(item_sprites(pk))
    icons, rows = {}, []
    for full, v in items.items():
        p = v['props']
        if 'food' not in p.get('ItemType', '').lower():   # also skips partial overrides of vanilla items (no ItemType)
            continue
        rep = p.get('ReplaceOnUse')
        tags = p.get('Tags', '').lower()
        hunger, thirst = num(p.get('HungerChange')), num(p.get('ThirstChange'))
        auto = None
        if not hunger and not thirst:
            auto = 'no nutrition: ignored by rule'
        elif not rep and p.get('CannedFood') == 'true':
            auto = 'closed can: exempt by rule'
        elif not rep and ('preservedfood' in tags or full in jars):
            auto = 'closed jar: exempt by rule'
        short = full.split('.', 1)[1]
        flags = []
        if short.startswith(('FoodStorageContainer', 'MetalFoodStorageContainer')):
            flags.append('storage-container')
        if rep:
            flags.append('vessel:' + rep.split('.')[-1])
        if p.get('Packaged') == 'true':
            flags.append('packaged')
        if p.get('CantEat') == 'true':
            flags.append('cant-eat')
        icon = p.get('Icon')
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
            'id': full, 'name': display.replace('_', ' '),
            'cat': re.sub(r'^[^-_]*[-_](items[-_])?(food[-_])?|\.txt$', '', v['file']) or v['file'], 'flags': flags,
            'sugg': bool(hunger and ((rep and rep in vessels) or LIQUID_NAME.search(display))),   # only a suggestion for the Liquid flag
            'hunger': hunger, 'thirst': thirst, 'auto': auto, 'base': None if cfg.get('editable') else rules.get(full), 'seed': cfg.get('seed_food', {}).get(full), 'icon': icon,
        })
    rows.sort(key=lambda r: (r['cat'], r['name'].lower()))
    icons = {k: v for k, v in icons.items() if v}
    modules = {}
    for r in rows:
        modules[r['id'].split('.')[0]] = modules.get(r['id'].split('.')[0], 0) + 1
    strip = max(modules, key=modules.get) + '.' if modules else ''

    html = open(os.path.join(HERE, 'template.html'), encoding='utf8').read()
    for a, b in (('__TITLE__', cfg['title']), ('__KEY__', cfg.get('storage', 'dstb-food-marks-' + key)), ('__STRIP__', strip),
                 ('__ROWS__', json.dumps(rows, separators=(',', ':'))), ('__ICONS__', json.dumps(icons, separators=(',', ':')))):
        html = html.replace(a, b)
    out = os.path.join(HERE, f'food-rules-{key}.html')
    open(out, 'w', encoding='utf8').write(html)
    print(f"{key}: {len(rows)} foods | {sum(1 for r in rows if r['auto'])} handled by rule | "
          f"{sum(1 for r in rows if r['base'])} in DSTB_Config | {sum(1 for r in rows if r['icon'] not in icons)} without icon | "
          f"modules {modules} | {round(os.path.getsize(out) / 1e6, 1)} MB -> {os.path.basename(out)}")


def main():
    keys = sys.argv[1:] or list(MODS)
    for k in keys:
        build(k)


if __name__ == '__main__':
    sys.exit(main())
