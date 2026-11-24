#!/usr/bin/env python3
"""grid_prepare.py: a visionOS work copy of GRID Legends' executable, with VXpro's macho_prepare.py and GRID's library map.

    tools/grid_prepare.py [--game /Applications/GRIDLegends.app] [--platform xros|xrsim] [--out DIR] [--check-imports]

Writes DIR/GRIDLegends.dylib (default build/prepared/Frameworks, or build/prepared_sim/Frameworks for xrsim) and
GRIDLegends.vxmac.plist (entry offset, source SHA-256). The App Store bundle is only read. --check-imports then runs
VXpro's check_imports.py against the built shims (make -C shims [sim]) and fails on a non-weak missing symbol.

The library map: VXpro's SHIMMED (AppKit -> libvxkit, ...) with GRID's gl* libraries in front, each re-exporting the VXpro
shim or the visionOS framework of the same name and adding what GRID imports beyond it (shims/README.md).
"""
import argparse, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VXPRO = os.path.join(HERE, 'third_party', 'VXpro')
sys.path.insert(0, os.path.join(VXPRO, 'tools'))
import macho_prepare  # noqa: E402

GRID_SHIMMED = {
    'AppKit': '@rpath/libglkit.dylib',              # libvxkit + NSApplicationMain, alerts, panels, Touch Bar
    'Carbon': '@rpath/libglcarbon.dylib',           # Text Input Sources, Carbon event loop
    'IOKit': '@rpath/libgliokit.dylib',             # libvxiokit + refused notification ports made quiet stand-ins
    'CoreGraphics': '@rpath/libglcg.dylib',         # libvxcg + events, gamma, display/window lists
    'Security': '@rpath/libglsec.dylib',            # libvxsec + legacy keychain
    'Metal': '@rpath/libglmtl.dylib',               # libvxmtl + device notifications
    'CoreServices': '@rpath/libglcs.dylib',         # Gestalt, Launch Services, UCKeyTranslate, libm
    'CoreVideo': '@rpath/libglcv.dylib',            # CVDisplayLink
    'CoreFoundation': '@rpath/libglcf.dylib',       # CFBundleGetMainBundle -> the game's bundle
    'Foundation': '@rpath/libglfoundation.dylib',   # NSUserNotificationCenter, +[NSBundle mainBundle] for the game
    'AVFoundation': '@rpath/libglavf.dylib',        # AVCaptureScreenInput
    'CoreAudio': '@rpath/libglca.dylib',            # HasProperty / listeners without the HAL (VXpro answers the rest)
    'WebKit': '@rpath/libglwebkit.dylib',           # WKWebView as is; the legacy WebView family as inert stand-ins
    'OpenAL': '@rpath/libglal.dylib',               # no device
    'ForceFeedback': '@rpath/libglff.dylib',        # no devices
    'Collaboration': '@rpath/libglcollab.dylib',    # CBIdentity
    'ApplicationServices': '@rpath/libglappsvc.dylib',   # (no symbols imported: empty libraries, one per
    'ScriptingBridge': '@rpath/libglsbridge.dylib',      #  framework, since dyld refuses an image naming one twice)
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--game', default='/Applications/GRIDLegends.app')
    ap.add_argument('--platform', choices=['xros', 'xrsim', 'macos'], default='xros')
    ap.add_argument('--out')
    ap.add_argument('--check-imports', action='store_true')
    a = ap.parse_args()
    exe = os.path.join(a.game, 'Contents', 'MacOS', 'GRIDLegends')
    if not os.path.exists(exe):
        raise SystemExit('not found: ' + exe)
    out = a.out or os.path.join(HERE, 'build', {'xros': 'prepared', 'xrsim': 'prepared_sim', 'macos': 'prepared_mac'}[a.platform], 'Frameworks')
    os.makedirs(out, exist_ok=True)
    dst = os.path.join(out, 'GRIDLegends.dylib')

    if a.platform != 'macos':
        macho_prepare.SHIMMED.update(GRID_SHIMMED)
        macho_prepare.SHIM_SYSTEM = '@rpath/libglsystem.dylib'   # (libvxsystem + pthread_main_np for the game thread)
    with tempfile.TemporaryDirectory() as t:
        thin = os.path.join(t, 'GRIDLegends')
        subprocess.run(['lipo', '-thin', 'arm64', exe, '-output', thin], check=True)
        sys.argv = ['macho_prepare.py', thin, dst, '--system-shim', '--as-dylib', '@rpath/GRIDLegends.dylib',
                    '--platform', a.platform, '--json', os.path.join(out, 'GRIDLegends.json')]
        if a.platform == 'macos':
            sys.argv.remove('--system-shim')
        import contextlib, io
        with contextlib.redirect_stdout(io.StringIO()):
            macho_prepare.main()
    names = subprocess.run(['otool', '-L', dst], capture_output=True, text=True, check=True).stdout.split('\n')[1:]
    names = [n.split(' (')[0].strip() for n in names if n.strip()]
    dup = sorted({n for n in names if names.count(n) > 1})
    if dup:
        raise SystemExit('the image names a library twice (dyld would refuse it): ' + ', '.join(dup))
    print('prepared', dst)

    if a.check_imports:
        shims = os.path.join(HERE, 'build', 'xrsim' if a.platform == 'xrsim' else 'xros')
        sdk = subprocess.run(['xcrun', '--sdk', 'xrsimulator' if a.platform == 'xrsim' else 'xros', '--show-sdk-path'],
                             capture_output=True, text=True, check=True).stdout.strip()
        r = subprocess.run([sys.executable, '-I', os.path.join(VXPRO, 'tools', 'check_imports.py'), dst,
                            '--shims', shims + ':' + out, '--sdk', sdk], capture_output=True, text=True)
        print(r.stdout.rstrip())
        if r.returncode or 'non-weak missing: 0' not in r.stdout:
            raise SystemExit('check_imports: missing symbols')


if __name__ == '__main__':
    main()
