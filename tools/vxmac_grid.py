#!/usr/bin/env python3
"""vxmac_grid.py: your own Mac App Store GRID Legends on your own Apple Vision Pro (VXpro's route, GRID's shims).

    tools/vxmac_grid.py prepare --team <TEAMID> [--game /Applications/GRIDLegends.app] [--bundle-id <id>] [--device <id>]
                                the shims and the game's executable as a visionOS work copy; settings -> build/grid/config.json
    tools/vxmac_grid.py build   [--splash image|title] [--quiet]  the host app signed with YOUR team, the work copy embedded
                                (--quiet: optimised, no log files, snapshots or frame bursts - for playing)
    tools/vxmac_grid.py install devicectl device install app (an update keeps the app's data: never uninstall)
    tools/vxmac_grid.py copy    the game's Info.plist, receipt and Resources (34 GB) into the app's container (resumable)
    tools/vxmac_grid.py launch  [--restart] [--present window|immersive] [--env NAME=VALUE ...]
                                (default: a floating window you can move and resize; immersive: VXpro's screen in a space)
    tools/vxmac_grid.py pull    [--tag <t>]   the logs back into build/grid/logs/<t>
    tools/vxmac_grid.py burst   [--tag <t>]   [--step N --frames N | --eyes]  frames of the running game (default every 2nd, 120) as PNGs in build/grid/logs/<t>
    tools/vxmac_grid.py pref    [--set 'Path\\Name=value' ...] [--unset 'Path\\Name' ...] [--show <text>]   Feral's settings file on the headset
                                (stops the game first; paths under HKEY_CURRENT_USER, e.g.
                                 'Software\\IndirectX\\Direct3D\\Config\\EnableF3DWarmer=0'; integers or text)

Commands that talk to the headset take --dry-run. Everything made here goes into build/ (git-ignored). The App Store
bundle is only read. Your receipt is copied unchanged: the game's activation needs it (docs/PHASE1.md).

NEVER uninstall GRID Legends Host and never install with --remove-existing-content: that deletes its container, the
copy of the game's data and your saves in it.
"""
import argparse, json, os, re, shutil, subprocess, sys, tempfile, time

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


def app_path():   # (the last build's: Debug, or Release for build --quiet)
    conf = load_config().get('build_configuration', 'Debug') if os.path.exists(CONFIG) else 'Debug'
    return os.path.join(DD, 'Build', 'Products', conf + '-xros', 'GRIDHost.app')


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
    # the window's splash until the first video (app/Sources/grid_splash.m), into build/:
    #   by default the game's own title screen, "LOADING" in place of "PRESS (A)" (tools/make_loading.swift)
    #   --splash IMAGE     any image instead, with "Loading..." under it (remembered in the config; --splash title: back)
    if a.splash == 'title': c.pop('splash', None)
    elif a.splash: c['splash'] = os.path.abspath(a.splash)
    if a.splash or 'loading' in c: c.pop('loading', None); json.dump(c, open(CONFIG, 'w'), indent=1)
    cat = os.path.join(WORK, 'Assets.xcassets')
    def imageset(name, png):
        if not os.path.exists(os.path.join(cat, 'Contents.json')):
            os.makedirs(cat, exist_ok=True); json.dump({'info': {'author': 'xcode', 'version': 1}}, open(os.path.join(cat, 'Contents.json'), 'w'))
        iset = os.path.join(cat, name + '.imageset'); os.makedirs(iset, exist_ok=True)
        run(['sips', '-s', 'format', 'png', '--resampleWidth', '1920', png, '--out', os.path.join(iset, name + '.png')])
        json.dump({'images': [{'filename': name + '.png', 'idiom': 'universal'}], 'info': {'author': 'xcode', 'version': 1}},
                  open(os.path.join(iset, 'Contents.json'), 'w'))
    if c.get('splash'):
        if not os.path.exists(c['splash']): sys.exit('--splash: no such image: %s' % c['splash'])
        imageset('Splash', c['splash'])
        shutil.rmtree(os.path.join(cat, 'SplashText.imageset'), ignore_errors=True)
    else:
        out = os.path.join(WORK, 'loading')
        run(['xcrun', 'swift', os.path.join(HERE, 'tools', 'make_loading.swift'), c['game'], out])
        imageset('Splash', os.path.join(out, 'Splash.png')); imageset('SplashText', os.path.join(out, 'SplashText.png'))
    splash_music(c['game'], cat)
    appdir = os.path.join(HERE, 'app')
    run(['xcodegen'], cwd=appdir)
    # --quiet: Release (optimised), and GRID_QUIET: no log files, snapshots or frame bursts (tools/sync_host.py hook 7)
    conf = 'Release' if a.quiet else 'Debug'
    run(['xcodebuild', '-project', 'GRIDHost.xcodeproj', '-scheme', 'GRIDHost', '-configuration', conf,
         '-destination', 'generic/platform=visionOS', '-derivedDataPath', DD, '-allowProvisioningUpdates', 'build',
         'DEVELOPMENT_TEAM=' + c['team'], 'GRID_BUNDLE_ID=' + c['bundle_id']]
        + (['GCC_PREPROCESSOR_DEFINITIONS=$(inherited) GRID_QUIET=1'] if a.quiet else []), cwd=appdir)
    c['build_configuration'] = conf; json.dump(c, open(CONFIG, 'w'), indent=1)
    app = app_path()
    if not os.path.exists(os.path.join(app, 'Frameworks', 'GRIDLegends.dylib')): sys.exit('not embedded: Frameworks/GRIDLegends.dylib')
    r = subprocess.run(['codesign', '-d', '--entitlements', '-', '--xml', app], capture_output=True, text=True)
    for e in ('com.apple.developer.kernel.increased-memory-limit', 'com.apple.developer.kernel.extended-virtual-addressing'):
        if e not in r.stdout: sys.exit('the signed app lacks %s (a paid team is needed)' % e)
    say('built: %s (signed by your team; do not share it: it contains the game\'s code)' % app)


def splash_music(game, cat):
    """The title screen's song (the game's Wwise stream Music_FE_Boot_Start_Screen_Loop, which loops whole) as the
    "SplashMusic" data asset, looped under the splash (app/Sources/grid_splash.m). Decoded with vgmstream-cli
    (brew install vgmstream) into Apple Lossless, so the loop has no gap; without vgmstream the splash is silent."""
    ds = os.path.join(cat, 'SplashMusic.dataset')
    shutil.rmtree(ds, ignore_errors=True)
    banks = os.path.join(game, 'Contents', 'Resources', 'Data', 'data_win', 'audio', 'soundbanks')
    try: info = open(os.path.join(banks, 'soundbanksinfo.xml'), encoding='utf-8', errors='replace').read()
    except OSError: say('splash music: no soundbanksinfo.xml in the game: silent splash'); return
    m = re.search(r'<File Id="(\d+)"[^>]*>\s*<ShortName>Music_FE_Boot_Start_Screen_Loop[^<]*</ShortName>', info)
    wem = m and os.path.join(banks, 'streams', m.group(1) + '.wem')
    if not wem or not os.path.exists(wem): say('splash music: the title song is not in the game\'s soundbanks: silent splash'); return
    tool = shutil.which('vgmstream-cli')
    if not tool: say('splash music: skipped - vgmstream-cli is not installed (brew install vgmstream): silent splash'); return
    out = os.path.join(WORK, 'loading'); os.makedirs(out, exist_ok=True)
    wav, caf = os.path.join(out, 'music.wav'), os.path.join(out, 'music.caf')
    run([tool, '-o', wav, wem])
    exit_ms = music_exit_ms(banks, int(m.group(1)))
    if exit_ms: loop_at(wav, exit_ms)
    else: say('splash music: no exit cue found in the music banks: the whole stream loops')
    run(['afconvert', '-f', 'caff', '-d', 'alac', wav, caf])
    os.makedirs(ds)
    shutil.copy(caf, os.path.join(ds, 'music.caf'))
    json.dump({'data': [{'filename': 'music.caf', 'idiom': 'universal', 'universal-type-identifier': 'com.apple.coreaudio-format'}],
               'info': {'author': 'xcode', 'version': 1}}, open(os.path.join(ds, 'Contents.json'), 'w'))


def music_exit_ms(banks, source_id):
    """The exit cue (ms) of the Wwise music segment that plays the stream: the game starts the next repeat there, while
    the stream's tail (its reverb, past the cue) still plays. From the soundbanks' HIRC: the music track (type 0x0B)
    naming the source, the music segment (0x0A) naming the track, and its markers (entry, exit: id, position as a
    double in ms, name)."""
    import glob, struct
    src = struct.pack('<I', source_id)
    for f in sorted(glob.glob(os.path.join(banks, '*.bnk'))):
        d = open(f, 'rb').read()
        if src not in d: continue
        i = 0
        while i + 8 <= len(d):
            tag, n = d[i:i + 4], struct.unpack('<I', d[i + 4:i + 8])[0]
            if tag == b'HIRC':
                j, objs = i + 12, []
                for _ in range(struct.unpack('<I', d[i + 8:i + 12])[0]):
                    t, ln = d[j], struct.unpack('<I', d[j + 1:j + 5])[0]
                    objs.append((t, d[j + 5:j + 5 + ln])); j += 5 + ln
                for t, b in objs:
                    if t != 0x0B or src not in b: continue
                    tid = b[:4]
                    for t2, seg in objs:
                        if t2 != 0x0A or tid not in seg[4:]: continue
                        for k in range(len(seg) - 4):   # (the markers end the segment's data)
                            c, p, marks = struct.unpack('<I', seg[k:k + 4])[0], k + 4, []
                            if not 2 <= c <= 8: continue
                            for _ in range(c):
                                if p + 16 > len(seg): break
                                pos, sl = struct.unpack('<d', seg[p + 4:p + 12])[0], struct.unpack('<I', seg[p + 12:p + 16])[0]
                                if not 0 <= pos < 600000 or sl > 64: break
                                marks.append(pos); p += 16 + sl
                            if len(marks) == c and p == len(seg) and marks[-1] > 0: return marks[-1]
            i += 8 + n
    return None


def loop_at(wav, exit_ms):
    """The stream as one seamless repeat of exit_ms: what follows the cue (the tail) is mixed into the start, as it
    sounds when the game repeats the segment."""
    import array, wave
    w = wave.open(wav); ch, rate, width, n = w.getnchannels(), w.getframerate(), w.getsampwidth(), w.getnframes()
    if width != 2: w.close(); return
    a = array.array('h'); a.frombytes(w.readframes(n)); w.close()
    L = int(round(exit_ms * rate / 1000.0))
    if not 0 < L < n: return
    out = array.array('h', a[:L * ch])
    for i in range(min(len(a) - L * ch, L * ch)):
        out[i] = max(-32768, min(32767, out[i] + a[L * ch + i]))
    o = wave.open(wav, 'wb'); o.setnchannels(ch); o.setsampwidth(2); o.setframerate(rate); o.writeframes(out.tobytes()); o.close()
    say('splash music: loops at the exit cue, %.3f s (the tail mixed into the start)' % (L / rate))


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
    # (--eyes: the window's stereo instead - the two eyes, the frame and its depth, once; app/Sources/grid_stereo.m)
    with tempfile.NamedTemporaryFile('w', delete=False) as f: f.write('%d %d' % (a.step, a.frames)); req = f.name
    devicectl(['device', 'copy', 'to'] + dom + ['--source', req, '--destination', 'Documents/' + ('grid_eyes' if a.eyes else 'grid_burst')])
    os.unlink(req)
    wait = min(a.wait, 4) if a.eyes else a.wait
    say('%s asked for: waiting %d s' % ('eyes' if a.eyes else 'burst', wait)); time.sleep(wait)
    raw = os.path.join(out, 'raw')
    devicectl(['device', 'copy', 'from'] + dom + ['--source', 'Documents/' + ('eyes' if a.eyes else 'burst'), '--destination', raw])
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
    p = sp.add_parser('build'); p.add_argument('--splash', help='an image for the window while the game starts instead of the '
                                               'title screen (remembered; "title" goes back to the title screen)')
    p.add_argument('--quiet', action='store_true', help='Release, no log files, snapshots or frame bursts (for playing)')
    p = sp.add_parser('burst'); p.add_argument('--tag'); p.add_argument('--wait', type=int, default=10)
    p.add_argument('--step', type=int, default=2, help='every Nth frame'); p.add_argument('--frames', type=int, default=120)
    p.add_argument('--eyes', action='store_true', help="the window's stereo: both eyes, the frame and its depth, once")
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
