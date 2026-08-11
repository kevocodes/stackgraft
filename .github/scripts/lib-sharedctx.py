"""Derive each unit's own tree under a shared build context.

`references/discovery.md` says a shared context is not any one unit's `paths`,
and the file that builds each one says which tree is. This is that derivation,
in one place so the row asserting it and the prose stating it cannot drift.
"""
import json, os, subprocess, sys
from collections import Counter

root = sys.argv[1]
model = json.loads(subprocess.run(
    ['docker', 'compose', '-f', os.path.join(root, 'compose.yaml'),
     'config', '--no-interpolate', '--format', 'json'],
    capture_output=True, text=True, check=True).stdout)

ctx, dockerfile = {}, {}
for name, svc in (model.get('services') or {}).items():
    build = svc.get('build') or {}
    raw = str(build.get('context') or '')
    ctx[name] = raw[len(root) + 1:] if raw.startswith(root + '/') else raw
    dockerfile[name] = build.get('dockerfile') or 'Dockerfile'

shared = {c for c, n in Counter(ctx.values()).items() if n > 1}
own = {}
for name, c in ctx.items():
    # A dockerfile at the context root means the unit is built from the whole
    # shared tree and genuinely consumes all of it.
    sub = os.path.dirname(dockerfile[name]) if c in shared else ''
    own[name] = os.path.join(c, sub) if sub else c

def selects(path):
    return sorted(n for n, p in own.items()
                  if path == p or path.startswith(p.rstrip('/') + '/'))

print('{}|{}|{}'.format(
    ','.join(selects('backend/alpha_service/app.py')),
    ','.join(selects('backend/shared_util.py')),
    ','.join(sorted(shared))))
