#!/usr/bin/env python3
"""vxmac_grid.py: your own Mac App Store GRID Legends on your own Apple Vision Pro (VXpro's route, GRID's shims).

    tools/vxmac_grid.py prepare --team <TEAMID> [--game /Applications/GRIDLegends.app] [--bundle-id <id>] [--device <id>]
                                the shims and the game's executable as a visionOS work copy; settings -> build/grid/config.json
    tools/vxmac_grid.py build   GRID Legends Host signed with YOUR team, the work copy embedded
    tools/vxmac_grid.py install devicectl device install app (an update keeps the app's data: never uninstall)
    tools/vxmac_grid.py copy    the game's Info.plist, receipt and Resources (34 GB) into the app's container (resumable)
    tools/vxmac_grid.py launch  [--restart] [--present window|immersive] [--env NAME=VALUE ...]
                                (default: a floating window you can move and resize; immersive: VXpro's screen in a space)
    tools/vxmac_grid.py pull    [--tag <t>]   the logs back into build/grid/logs/<t>
    tools/vxmac_grid.py burst   [--tag <t>]   [--step N --frames N]  frames of the running game (default every 2nd, 120) as PNGs in build/grid/logs/<t>
    tools/vxmac_grid.py pref    [--set 'Path\\Name=value' ...] [--unset 'Path\\Name' ...] [--show <text>]   Feral's settings file on the headset
                                (stops the game first; paths under HKEY_CURRENT_USER, e.g.
                                 'Software\\IndirectX\\Direct3D\\Config\\EnableF3DWarmer=0'; integers or text)

Commands that talk to the headset take --dry-run. Everything made here goes into build/ (git-ignored). The App Store
bundle is only read. Your receipt is copied unchanged: the game's activation needs it (docs/PHASE1.md).

NEVER uninstall GRID Legends Host and never install with --remove-existing-content: that deletes its container, the
copy of the game's data and your saves in it.
"""
import argparse, json, os, re, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(HERE, 'build', 'grid')
CONFIG = os.path.join(WORK, 'config.json')
PREPARED = os.path.join(HERE, 'build', 'prepared', 'Frameworks')
DD = os.path.join(HERE, 'build', 'dd_device')
DST = 'Documents/GRIDLegends.app/Contents'


def say(s): print(s, flush=True)


def run(cmd, dry=False, check=True, cwd=None, env=None):
    say('$ ' + ' '.join(cmd))
    if dry: return subprocess.CompletedProcess(cmd, 0, '', '')
    r = subprocess.run(cmd, cwd=cwd, env=env)
    if check and r.returncode: sys.exit('failed (%d): %s' % (r.returncode, ' '.join(cmd)))
    return r


def devicectl(args, dry=False, check=True):
    return run(['xcrun', 'devicectl', *args], dry=dry, check=check)


def load_config():
    if not os.path.exists(CONFIG): sys.exit('no config: run prepare first')
    return json.load(open(CONFIG))


def first_headset():
    with tempfile.NamedTemporaryFile(suffix='.json') as t:
        subprocess.run(['xcrun', 'devicectl', 'list', 'devices', '--json-output', t.name], capture_output=True)
        d = json.load(open(t.name))
    for dev in d.get('result', {}).get('devices', []):
        hw = dev.get('hardwareProperties', {})
        if hw.get('platform') == 'xrOS' and hw.get('reality') == 'physical':
            return hw.get('udid')
    return None


def app_path():
    return os.path.join(DD, 'Build', 'Products', 'Debug-xros', 'GRIDHost.app')


# ---- prepare / build ---------------------------------------------------------------------------------------------------
def cmd_prepare(a):
    if not re.fullmatch(r'[A-Z0-9]{10}', a.team or ''): sys.exit('--team: your 10-character Apple Developer team ID')
    dev = a.device or first_headset()
    if not dev: sys.exit('no paired Apple Vision Pro found: pair it in Xcode (Window > Devices and Simulators) or pass --device')
    c = {'game': a.game, 'team': a.team, 'bundle_id': a.bundle_id or 'com.%s.gridhost' % a.team.lower(), 'device': dev}
    os.makedirs(WORK, exist_ok=True)
    json.dump(c, open(CONFIG, 'w'), indent=1)
    run(['make', '-C', os.path.join(HERE, 'shims')])
    run([sys.executable, '-I', os.path.join(HERE, 'tools', 'grid_prepare.py'), '--game', a.game, '--check-imports'])
    say('prepared: team %s, bundle id %s, headset %s' % (c['team'], c['bundle_id'], dev))


def cmd_build(a):
    c = load_config()
    if not os.path.exists(os.path.join(PREPARED, 'GRIDLegends.dylib')): sys.exit('no work copy: run prepare')
    run([sys.executable, '-I', os.path.join(HERE, 'tools', 'sync_host.py'), '--check'])
    icns = os.path.join(c['game'], 'Contents', 'Resources', 'GameIcon.icns')
    if os.path.exists(icns):  # the home-screen icon, made from the game's own (into build/, never into git)
        run(['xcrun', 'swift', os.path.join(HERE, 'tools', 'make_icon.swift'), icns, os.path.join(WORK, 'Assets.xcassets')])
    appdir = os.path.join(HERE, 'app')
    run(['xcodegen'], cwd=appdir)
    run(['xcodebuild', '-project', 'GRIDHost.xcodeproj', '-scheme', 'GRIDHost', '-destination', 'generic/platform=visionOS',
         '-derivedDataPath', DD, '-allowProvisioningUpdates', 'build', 'DEVELOPMENT_TEAM=' + c['team'],
         'GRID_BUNDLE_ID=' + c['bundle_id']], cwd=appdir)
    app = app_path()
    if not os.path.exists(os.path.join(app, 'Frameworks', 'GRIDLegends.dylib')): sys.exit('not embedded: Frameworks/GRIDLegends.dylib')
    r = subprocess.run(['codesign', '-d', '--entitlements', '-', '--xml', app], capture_output=True, text=True)
    for e in ('com.apple.developer.kernel.increased-memory-limit', 'com.apple.developer.kernel.extended-virtual-addressing'):
        if e not in r.stdout: sys.exit('the signed app lacks %s (a paid team is needed)' % e)
    say('built: %s (signed by your team; do not share it: it contains the game\'s code)' % app)


# ---- install / copy ---------------------------------------------------------------------------------------------------
def cmd_install(a):
    c = load_config()
    app = app_path()
    if not a.dry_run and not os.path.exists(app): sys.exit('no app: run build')
    devicectl(['device', 'install', 'app', '--device', c['device'], app], dry=a.dry_run)


def copy_items(game):
    """(source, destination) pairs, small first: the Info.plist, the receipt, Resources' small entries, then the Data
    folders one by one, so a failed copy resumes at the folder it stopped in."""
    res = os.path.join(game, 'Contents', 'Resources')
    items = [(os.path.join(game, 'Contents', 'Info.plist'), DST + '/Info.plist')]
    receipt = os.path.join(game, 'Contents', '_MASReceipt', 'receipt')
    if os.path.exists(receipt): items.append((receipt, DST + '/_MASReceipt/receipt'))
    for name in sorted(os.listdir(res)):
        if name != 'Data': items.append((os.path.join(res, name), DST + '/Resources/' + name))
    data = os.path.join(res, 'Data')
    for name in sorted(os.listdir(data)):
        p = os.path.join(data, name)
        if os.path.isdir(p) and name in ('data', 'data_win'):
            for sub in sorted(os.listdir(p)):
                items.append((os.path.join(p, sub), '%s/Resources/Data/%s/%s' % (DST, name, sub)))
        else:
            items.append((p, '%s/Resources/Data/%s' % (DST, name)))
    return items


def cmd_copy(a):
    c = load_config()
    logd = os.path.join(WORK, 'copy'); os.makedirs(logd, exist_ok=True)
    done_f = os.path.join(logd, 'done.txt')
    done = set(open(done_f).read().split('\n')) if os.path.exists(done_f) else set()
    items = copy_items(c['game'])
    say('%d items to copy; done before: %d. Keep the headset awake and on its charger.' % (len(items), sum(1 for _, d in items if d in done)))
    for src, dst in items:
        if dst in done: continue
        for attempt in range(1, a.tries + 1):
            r = devicectl(['device', 'copy', 'to', '--device', c['device'], '--domain-type', 'appDataContainer',
                           '--domain-identifier', c['bundle_id'], '--source', src, '--destination', dst, '--timeout', '7200'],
                          dry=a.dry_run, check=False)
            if r.returncode == 0:
                if not a.dry_run:
                    with open(done_f, 'a') as f: f.write(dst + '\n')
                break
            say('  failed (try %d of %d): %s; waiting 60 s' % (attempt, a.tries, dst)); time.sleep(60)
        else:
            sys.exit('stopped at %s: run copy again to resume' % dst)
    verify(c, a.dry_run)


def device_files(c):
    with tempfile.NamedTemporaryFile(suffix='.json') as t:
        r = subprocess.run(['xcrun', 'devicectl', 'device', 'info', 'files', '--device', c['device'], '--domain-type',
                            'appDataContainer', '--domain-identifier', c['bundle_id'], '--subdirectory', DST,
                            '--json-output', t.name], capture_output=True, text=True)
        if r.returncode: return {}
        d = json.load(open(t.name))
    return {f['relativePath']: f['metadata']['size'] for f in d.get('result', {}).get('files', []) if not f['resources']['isDirectory']}


def verify(c, dry):
    if dry: say('(dry run: no check)'); return
    dev = device_files(c)
    src = os.path.join(c['game'], 'Contents')
    n = b = bad = 0
    for root, ds, fs in os.walk(src):
        rel_root = os.path.relpath(root, src)
        if rel_root.split(os.sep)[0] in ('MacOS', 'Frameworks', '_CodeSignature'): continue
        for name in fs:
            if rel_root == '.' and name != 'Info.plist': continue
            p = os.path.join(root, name); rel = os.path.normpath(os.path.join(rel_root, name)); s = os.path.getsize(p)
            n += 1; b += s
            if dev.get(rel) != s:
                bad += 1
                if bad <= 20: say('  missing or wrong size: %s' % rel)
    say('check: source %d files %.1f GB; headset %d files %.1f GB; mismatches %d -> %s'
        % (n, b / 1e9, len(dev), sum(dev.values()) / 1e9, bad, 'OK' if not bad else 'INCOMPLETE: run copy again'))
    if bad:
        done_f = os.path.join(WORK, 'copy', 'done.txt')
        if os.path.exists(done_f): os.replace(done_f, done_f + '.%d' % int(time.time()))


# ---- launch / logs ----------------------------------------------------------------------------------------------------
def cmd_launch(a):
    c = load_config()
    args = ['device', 'process', 'launch', '--device', c['device']]
    if a.restart: args.append('--terminate-existing')
    extra = ['-present', 'vr'] if a.present == 'immersive' else []
    for kv in a.env:
        if '=' not in kv: sys.exit('--env NAME=VALUE')
        extra += ['-env', kv]
    devicectl(args + [c['bundle_id']] + (['--'] + extra if extra else []), dry=a.dry_run)
    say('put the headset on and unlock it: the game shows in a %s' % ('screen in an immersive space' if a.present == 'immersive' else 'floating window'))


def cmd_pull(a):
    c = load_config()
    out = os.path.join(WORK, 'logs', a.tag or time.strftime('%Y%m%d-%H%M%S')); os.makedirs(out, exist_ok=True)
    for name in ('vxmac_host.jsonl', 'vxmac_program.log', 'snap.png'):
        devicectl(['device', 'copy', 'from', '--device', c['device'], '--domain-type', 'appDataContainer', '--domain-identifier',
                   c['bundle_id'], '--source', 'Documents/' + name, '--destination', os.path.join(out, name)],
                  dry=a.dry_run, check=False)
    say('logs: %s (they name your files and device: do not post them unread)' % out)


def cmd_burst(a):
    """Frames of the running game: asks for a burst (app/Sources/grid_burst.m), copies it back, converts it to PNG."""
    import tempfile
    c = load_config()
    out = os.path.join(WORK, 'logs', a.tag or time.strftime('burst-%Y%m%d-%H%M%S')); os.makedirs(out, exist_ok=True)
    dom = ['--device', c['device'], '--domain-type', 'appDataContainer', '--domain-identifier', c['bundle_id']]
    with tempfile.NamedTemporaryFile('w', delete=False) as f: f.write('%d %d' % (a.step, a.frames)); req = f.name
    devicectl(['device', 'copy', 'to'] + dom + ['--source', req, '--destination', 'Documents/grid_burst'])
    os.unlink(req)
    say('burst asked for: waiting %d s' % a.wait); time.sleep(a.wait)
    raw = os.path.join(out, 'raw')
    devicectl(['device', 'copy', 'from'] + dom + ['--source', 'Documents/burst', '--destination', raw])
    idx = os.path.join(raw, 'index.txt')
    if not os.path.exists(idx): sys.exit('no frames came back (is the game running and in front?)')
    run(['xcrun', 'swift', os.path.join(HERE, 'tools', 'burst_png.swift'), raw, out])
    say('frames: %s' % out)


PREFS = 'Library/Application Support/Feral Interactive/GRIDLegends/Preferences Data'


def stop_game(c):
    r = subprocess.run(['xcrun', 'devicectl', 'device', 'info', 'processes', '--device', c['device']], capture_output=True, text=True)
    for line in r.stdout.splitlines():
        if 'GRIDHost.app/GRIDHost' in line:
            pid = line.split()[0]
            devicectl(['device', 'process', 'terminate', '--device', c['device'], '--pid', pid], check=False)
            time.sleep(2)


def cmd_pref(a):
    import xml.etree.ElementTree as ET
    c = load_config()
    if a.set or a.unset: stop_game(c)
    with tempfile.TemporaryDirectory() as t:
        local = os.path.join(t, 'prefs.xml')
        devicectl(['device', 'copy', 'from', '--device', c['device'], '--domain-type', 'appDataContainer', '--domain-identifier',
                   c['bundle_id'], '--source', PREFS, '--destination', local])
        tree = ET.parse(local); root = tree.getroot()
        hkcu = root.find("key[@name='HKEY_CURRENT_USER']")
        for kv in a.set:
            path, _, value = kv.partition('=')
            parts = path.split('\\')
            node = hkcu
            for name in parts[:-1]:
                child = node.find("key[@name='%s']" % name)
                if child is None: child = ET.SubElement(node, 'key', name=name)
                node = child
            v = node.find("value[@name='%s']" % parts[-1])
            if v is None: v = ET.SubElement(node, 'value', name=parts[-1])
            is_int = value.lstrip('-').isdigit()
            v.set('type', 'integer' if is_int else 'string'); v.text = value
            say('set %s = %s' % (path, value))
        for path in a.unset:
            parts = path.split('\\'); node = hkcu
            for name in parts[:-1]:
                node = node.find("key[@name='%s']" % name) if node is not None else None
            v = node.find("value[@name='%s']" % parts[-1]) if node is not None else None
            if v is not None: node.remove(v); say('unset %s (the game\'s default again)' % path)
        def walk(e, path):
            for ch in e:
                if ch.tag == 'key': yield from walk(ch, path + [ch.get('name')])
                elif ch.tag == 'value': yield '\\'.join(path + [ch.get('name')]), ch.text
        if a.show:
            for k, v in walk(hkcu, []):
                if a.show.lower() in k.lower(): say('%s = %s' % (k, v))
        if a.set or a.unset:
            tree.write(local, encoding='UTF-8', xml_declaration=True)
            devicectl(['device', 'copy', 'to', '--device', c['device'], '--domain-type', 'appDataContainer', '--domain-identifier',
                       c['bundle_id'], '--source', local, '--destination', PREFS])


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = ap.add_subparsers(dest='cmd', required=True)
    p = sp.add_parser('prepare'); p.add_argument('--game', default='/Applications/GRIDLegends.app'); p.add_argument('--team')
    p.add_argument('--bundle-id'); p.add_argument('--device')
    sp.add_parser('build')
    p = sp.add_parser('burst'); p.add_argument('--tag'); p.add_argument('--wait', type=int, default=10)
    p.add_argument('--step', type=int, default=2, help='every Nth frame'); p.add_argument('--frames', type=int, default=120)
    p = sp.add_parser('pref'); p.add_argument('--set', action='append', default=[]); p.add_argument('--show')
    p.add_argument('--unset', action='append', default=[])
    for name in ('install', 'copy', 'launch', 'pull'):
        p = sp.add_parser(name); p.add_argument('--dry-run', action='store_true')
        if name == 'copy': p.add_argument('--tries', type=int, default=8)
        if name == 'launch':
            p.add_argument('--restart', action='store_true', help='end a running instance first (unsaved progress is lost)')
            p.add_argument('--present', choices=['window', 'immersive'], default='window')
            p.add_argument('--env', action='append', default=[], help='NAME=VALUE for the app')
        if name == 'pull': p.add_argument('--tag')
    a = ap.parse_args()
    return {'prepare': cmd_prepare, 'build': cmd_build, 'install': cmd_install, 'copy': cmd_copy,
            'launch': cmd_launch, 'pull': cmd_pull, 'pref': cmd_pref, 'burst': cmd_burst}[a.cmd](a) or 0


if __name__ == '__main__':
    sys.exit(main())
