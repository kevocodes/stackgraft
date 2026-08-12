"""Find stores by the state they hold, never by a name.

`references/discovery.md` says the signal is structural: a unit that mounts
something writable which outlives the container holds durable state, and durable
state the base stack runs is a store whatever it is called. This is that reading,
beside a name-matching one, so a row can show the two disagreeing on the shape
that actually occurs.
"""
import json, os, re, subprocess, sys

NAMES = re.compile(r'postgres|timescale|redis|valkey|mongo|mysql|mariadb|minio|kafka')

model = json.loads(subprocess.run(
    ['docker', 'compose', '-f', sys.argv[1], 'config', '--no-interpolate', '--format', 'json'],
    capture_output=True, text=True, check=True).stdout)
svcs = model.get('services') or {}

def durable(svc):
    # A named volume outlives the container. A read-only mount is not state this
    # unit holds, and a bind of source code is not state at all.
    return [v for v in (svc.get('volumes') or [])
            if v.get('type') == 'volume' and not v.get('read_only')]

by_state = sorted(n for n, s in svcs.items() if durable(s))
by_name  = sorted(n for n, s in svcs.items()
                  if NAMES.search(s.get('image') or '') and durable(s))
print('{}|{}'.format(','.join(by_state), ','.join(by_name)))
