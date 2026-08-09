#!/bin/sh
# The third floor: discovery, and the manifest it produces.
#
# The schema rows in verify.sh validate manifests somebody wrote by hand to be
# validated. No manifest that discovery actually produced from a real repository
# had ever been checked against that schema, so the question "does the shape
# this skill tells an agent to build satisfy the shape it also ships" had never
# been asked of a real answer.
#
# What is honest about this file, said before its rows are read: it IMPLEMENTS
# discovery's extraction rules for the container case rather than driving the
# document. That proves the rules are implementable, that their output validates,
# and that the derivations they name -- bindsTo out of the published spec, the
# store/service split, the mandatory -C on a fingerprint -- come out right. It
# does not prove an agent reading `references/discovery.md` arrives at the same
# manifest, which is a different claim needing a different instrument.
#
# usage: sh .github/scripts/integration-discovery.sh
set -u

checks=0
failures=0
skips=0

ok()   { checks=$((checks + 1)); printf '  ok    %s\n' "$1"; }
fail() { checks=$((checks + 1)); failures=$((failures + 1)); printf '  FAIL  %s\n' "$1"; }
skip() { skips=$((skips + 1));   printf '  skip  %s\n' "$1"; }

REPO=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd -P)
FIXTURE="$REPO/.github/fixtures/shopdemo"
SCRIPTS="$REPO/skills/stackgraft/scripts"
SCHEMA="$REPO/skills/stackgraft/assets/manifest.schema.json"

WORK="$REPO/.sg-work-discovery"
MAIN="$WORK/shopdemo"
TREE="$WORK/shopdemo-worktrees/topology-drift"
MANIFEST="$WORK/manifest.json"

cleanup() { rm -rf "$WORK"; return 0; }
trap cleanup EXIT INT TERM

printf '\ndiscovery, and the manifest it produces\n\n'

if ! docker info >/dev/null 2>&1; then
    skip 'no container runtime, so the resolver cannot answer and discovery is unexercised'
    if [ "${STACKGRAFT_REQUIRE_RUNTIME:-0}" = 1 ]; then
        printf '\n  a runtime was required and none answered\n\n'
        exit 1
    fi
    printf '\n  %s check(s) ran, %s skipped\n\n' "$checks" "$skips"
    exit 0
fi

if ! python3 -c 'import jsonschema' >/dev/null 2>&1; then
    skip 'no jsonschema, so the manifest cannot be validated against the shipped schema'
    if [ "${STACKGRAFT_REQUIRE_RUNTIME:-0}" = 1 ]; then
        printf '\n  a validator was required and none answered\n\n'
        exit 1
    fi
    printf '\n  %s check(s) ran, %s skipped\n\n' "$checks" "$skips"
    exit 0
fi

cleanup
mkdir -p "$MAIN"
cp -R "$FIXTURE/." "$MAIN/"
(
    cd "$MAIN" || exit 1
    git init -q -b main
    git add -A
    git -c user.email=fixture@example.com -c user.name=fixture commit -qm 'the shopdemo base stack'
) >/dev/null 2>&1
git -C "$MAIN" worktree add -q -b chore/topology-drift "$TREE" >/dev/null 2>&1

# --- section 1: prefer the ecosystem's own resolver over hand-parsing --------

RESOLVED="$WORK/resolved.json"
if docker compose -f "$MAIN/compose.yaml" config --format json > "$RESOLVED" 2>/dev/null; then
    ok "the ecosystem's own resolver answers, so no topology is hand-parsed"
else
    fail 'the resolver did not answer and this floor has nothing to extract from'
    exit 1
fi

# --- the fingerprint, with the -C the document calls mandatory --------------

FP=$(sh "$SCRIPTS/fingerprint.sh" -C "$MAIN" compose.yaml | awk '{print $1}')
case "$FP" in
    ''|-) fail "fingerprint.sh -C produced no value for compose.yaml: '$FP'" ;;
    *)    ok "compose.yaml fingerprints through the skill's own script: ${FP%"${FP#????????}"}…" ;;
esac

# `-C` is not optional, and this is the failure it prevents. `sources[].path` is
# relative to repoRoot while a run happens in the overlay's checkout, so the same
# relative path resolves to a different file there. One manifest is shared by
# every checkout, so a value taken without -C writes worktree-local topology into
# it and every other checkout then reads full drift.
printf '# a worktree-local edit\n' >> "$TREE/compose.yaml"
FP_WITH=$(cd "$TREE" && sh "$SCRIPTS/fingerprint.sh" -C "$MAIN" compose.yaml | awk '{print $1}')
FP_WITHOUT=$(cd "$TREE" && sh "$SCRIPTS/fingerprint.sh" compose.yaml | awk '{print $1}')
if [ "$FP_WITH" = "$FP" ] && [ "$FP_WITHOUT" != "$FP" ]; then
    ok 'from inside a worktree, -C still fingerprints the main checkout and its absence fingerprints the worktree, which is the drift -C exists to prevent'
else
    fail "the -C distinction did not hold: main=$FP with-C=$FP_WITH without-C=$FP_WITHOUT"
fi
git -C "$TREE" checkout -q -- compose.yaml 2>/dev/null || true

# --- the serviceFingerprint recipe, which nothing had ever reproduced -------
# Three legs piped in order into `git hash-object --stdin`, per the recipe at
# the end of references/shared-state.md. The globs are :(glob) pathspecs and
# stay quoted, so git expands them and not the shell -- an unquoted glob is
# expanded by a shell that skips dotfiles, and a dropped .env.example is a file
# whose every later edit leaves the value exactly where it was.
service_fingerprint() {
    _tree=$1
    shift
    {
        for _p in "$@"; do
            git -C "$_tree" ls-files -s -- ":(glob)$_p/**" ":(glob)$_p"
        done
        for _p in "$@"; do
            git -C "$_tree" diff --no-color --binary --no-ext-diff --no-textconv \
                -- ":(glob)$_p/**" ":(glob)$_p"
        done
        for _p in "$@"; do
            git -C "$_tree" -c core.quotePath=false ls-files --others --exclude-standard \
                -- ":(glob)$_p/**" ":(glob)$_p"
        done | ( cd "$_tree" && sh "$SCRIPTS/fingerprint.sh" - )
    } | git hash-object --stdin
}

python3 - "$RESOLVED" "$MAIN" > "$WORK/units.tsv" <<'PY'
import json, sys, re
model = json.load(open(sys.argv[1])); root = sys.argv[2]
ENGINES = re.compile(r'postgres|postgresql|timescale|redis|valkey|mongo|mysql|mariadb|kafka|rabbitmq|elasticsearch|opensearch|minio|nats|clickhouse|cassandra|memcached')
for name, svc in (model.get('services') or {}).items():
    named = [v for v in (svc.get('volumes') or []) if v.get('type') == 'volume']
    if ENGINES.search(svc.get('image') or '') and named:
        continue
    binds = sorted({str(v['source'])[len(root)+1:] for v in (svc.get('volumes') or []) if v.get('type') == 'bind'})
    print('{}\t{}'.format(name, ','.join(binds)))
PY

: > "$WORK/fps.tsv"
while IFS="$(printf '\t')" read -r unit paths; do
    [ -n "$unit" ] || continue
    # shellcheck disable=SC2086
    fp=$(service_fingerprint "$MAIN" $(printf '%s' "$paths" | tr ',' ' '))
    printf '%s\t%s\n' "$unit" "$fp" >> "$WORK/fps.tsv"
done < "$WORK/units.tsv"

BASE_FP=$(awk -F'\t' '$1=="catalog-api"{print $2}' "$WORK/fps.tsv")
case "$BASE_FP" in
    ''|*[!0-9a-f]*) fail "the serviceFingerprint recipe produced no hash: '$BASE_FP'" ;;
    *) ok "the serviceFingerprint recipe produces a value over the unit's own paths: ${BASE_FP%"${BASE_FP#????????}"}…" ;;
esac

# The document claims a staged-only edit, an unstaged-only edit and a new
# untracked file each move it, and that reverting returns it to the exact base.
# It says that was verified on a scratch repository; nothing reproduced it here.
printf '\n# unstaged\n' >> "$MAIN/services/catalog-api/handle.sh"
FP_UNSTAGED=$(service_fingerprint "$MAIN" services/catalog-api)
git -C "$MAIN" add services/catalog-api/handle.sh >/dev/null 2>&1
FP_STAGED=$(service_fingerprint "$MAIN" services/catalog-api)
printf 'x\n' > "$MAIN/services/catalog-api/untracked.txt"
FP_UNTRACKED=$(service_fingerprint "$MAIN" services/catalog-api)
rm -f "$MAIN/services/catalog-api/untracked.txt"
git -C "$MAIN" checkout -q -- services/catalog-api 2>/dev/null
git -C "$MAIN" reset -q HEAD -- services/catalog-api 2>/dev/null
git -C "$MAIN" checkout -q -- services/catalog-api 2>/dev/null
FP_REVERTED=$(service_fingerprint "$MAIN" services/catalog-api)

[ "$FP_UNSTAGED" != "$BASE_FP" ] \
    && ok 'an unstaged edit inside the unit moves its serviceFingerprint' \
    || fail 'an unstaged edit did not move the serviceFingerprint, so a changed service reads as unchanged'
[ "$FP_STAGED" != "$BASE_FP" ] \
    && ok 'a staged edit moves it too, so staging does not hide a change from the gate' \
    || fail 'a staged edit did not move the serviceFingerprint'
[ "$FP_UNTRACKED" != "$FP_STAGED" ] \
    && ok 'a new untracked file inside the unit moves it, which is the third leg of the recipe' \
    || fail 'an untracked file did not move the serviceFingerprint'
[ "$FP_REVERTED" = "$BASE_FP" ] \
    && ok 'reverting every mutation returns it to the exact base, so the value is content-derived and not path-dependent' \
    || fail "reverting did not restore the base value: $FP_REVERTED against $BASE_FP"

# --- extract per the document's rules, out of the resolver's answer ---------

python3 - "$RESOLVED" "$MAIN" "$FP" "$MANIFEST" "$WORK/fps.tsv" <<'PY'
import json, sys, re

resolved_path, repo_root, fingerprint, out, fps_path = sys.argv[1:6]
model = json.load(open(resolved_path))
fps = dict(
    line.rstrip('\n').split('\t', 1)
    for line in open(fps_path) if '\t' in line
)

ENGINES = re.compile(
    r'postgres|postgresql|timescale|redis|valkey|mongo|mysql|mariadb|kafka|'
    r'rabbitmq|elasticsearch|opensearch|minio|nats|clickhouse|cassandra|memcached'
)

def rel(p):
    p = str(p)
    return p[len(repo_root) + 1:] if p.startswith(repo_root + '/') else p

def published(svc):
    out = []
    for p in svc.get('ports') or []:
        out.append({
            'host_ip': p.get('host_ip') or '0.0.0.0',
            'published': int(p.get('published')),
        })
    return out

services, stores = {}, {}
reserved, binds = [], set()

for name, svc in (model.get('services') or {}).items():
    image = svc.get('image') or ''
    named_volumes = [v for v in (svc.get('volumes') or []) if v.get('type') == 'volume']
    bind_paths = sorted({rel(v['source']) for v in (svc.get('volumes') or []) if v.get('type') == 'bind'})

    for spec in published(svc):
        reserved.append(spec['published'])
        binds.add(spec['host_ip'])

    # A store is an engine image that holds state of its own. A service that
    # only bind-mounts source is a runnable unit however store-shaped its image.
    if ENGINES.search(image) and named_volumes:
        hc = (svc.get('healthcheck') or {}).get('test') or []
        stores[name] = {
            'substrate': ENGINES.search(image).group(0),
            'locality': {
                'value': 'local',
                'reason': 'the resolver declares it here with a named volume on this host',
            },
            'isolation': {
                # No lifecycle target is discoverable anywhere in this repository,
                # which is the ordinary case rather than a degraded read.
                'mechanism': 'none',
                'discoveredFrom': 'compose.yaml',
                'confidence': 'declared',
            },
            # Why a mechanism is none is the record that stops the next pass
            # re-deriving one that does not work, and the two refusals are not
            # the same refusal: a CMD-SHELL test never becomes a candidate,
            # while an exec-form vector becomes one and is then refused by the
            # discriminator instead.
            'notes': [
                'healthcheck is {}: {}'.format(
                    hc[0] if hc else 'absent',
                    'shell source rather than an argument vector, so the argv rule '
                    'excludes it before anything else is asked' if hc[:1] == ['CMD-SHELL']
                    else 'an exec-form vector, so it IS a rung-1 candidate and has to be '
                    'held to the discriminator like any other' if hc
                    else 'no test is declared, so there is no rung-1 candidate to weigh',
                ),
            ],
        }
    else:
        entry = {
            'kind': 'container',
            'runnable': True,
            'confidence': 'declared',
            'paths': bind_paths or [rel(svc.get('build', {}).get('context', name))],
            'dependsOn': sorted((svc.get('depends_on') or {}).keys()),
            # Classification is only trustworthy with evidence of how it was
            # reached, which is why the schema requires this beside the claim.
            # {at, method, serviceFingerprint} and nothing else: how sure the
            # pass was lives on the entry, while this record carries the
            # baseline a later run compares against.
            'stateReview': {
                'at': '2026-08-09T00:00:00Z',
                'method': 'resolver-declared',
                'serviceFingerprint': fps.get(name, ''),
            },
        }
        spec = published(svc)
        if spec:
            entry['basePort'] = spec[0]['published']
            entry['portGroup'] = 'http'
        services[name] = entry

manifest = {
    'schemaVersion': 3,
    'repoRoot': repo_root,
    'discoveredAt': '2026-08-09T00:00:00Z',
    'fingerprintTool': 'git-hash-object-no-filters',
    'sources': [{
        'path': 'compose.yaml',
        'fingerprint': fingerprint,
        'revalidate': 'always',
        'confidence': 'declared',
        'covers': ['services', 'backingStores', 'baseStack', 'portPolicy'],
    }],
    'baseStack': {
        'startCommand': 'docker compose --project-directory {{repoRoot}} up -d',
        'statusCommand': "docker compose --project-directory {{repoRoot}} ps --format '{{.Service}} {{.State}} {{.Publishers}}'",
        'teardownCommand': 'docker compose --project-directory {{repoRoot}} stop',
        # Loopback only where every published spec says so; any bare form
        # publishes on every interface and the weaker reading wins.
        'bindsTo': '127.0.0.1' if binds == {'127.0.0.1'} else '0.0.0.0',
    },
    'backingStores': stores,
    'services': services,
    'portPolicy': {'reserved': sorted(reserved)},
}
json.dump(manifest, open(out, 'w'), indent=1)
PY

[ -s "$MANIFEST" ] && ok 'a manifest is produced from the resolver rather than from a hand-written fixture' \
                   || fail 'no manifest was produced'

# --- it validates against the schema this repository ships ------------------

if python3 - "$SCHEMA" "$MANIFEST" <<'PY'
import json, sys
from jsonschema import Draft202012Validator
schema = json.load(open(sys.argv[1]))
doc = json.load(open(sys.argv[2]))
errors = sorted(Draft202012Validator(schema).iter_errors(doc), key=lambda e: e.path)
for e in errors[:4]:
    print('  {}: {}'.format('/'.join(str(p) for p in e.path) or '<root>', e.message))
sys.exit(1 if errors else 0)
PY
then
    ok 'the produced manifest validates against the shipped schema, which no discovery output had ever been asked to do'
else
    fail 'the manifest discovery produces does not satisfy the schema this repository ships'
fi

# --- and it is right about the repository, not merely well-formed -----------

claim() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2], {}, {"d": d}))' "$MANIFEST" "$1" 2>/dev/null; }

[ "$(claim 'sorted(d["backingStores"])')" = "['postgres', 'sessions']" ] \
    && ok 'both stores are discovered as backing stores, and the pass does not stop at the first' \
    || fail "backingStores is wrong: $(claim 'sorted(d["backingStores"])')"

[ "$(claim 'sorted(d["services"])')" = "['catalog-api']" ] \
    && ok 'the runnable unit is discovered as a service, and the store is not one of them: catalog-api' \
    || fail "services is wrong: $(claim 'sorted(d["services"])')"

# The second store is the one that proves the rule: the service is named
# `sessions` and the substrate is `redis`, so a pass reading the key would get
# it wrong and a pass reading the image gets it right.
[ "$(claim 'd["backingStores"]["postgres"]["substrate"]')" = postgres ] \
    && ok 'the first substrate is read off the image' \
    || fail "substrate is wrong: $(claim 'd["backingStores"]["postgres"]["substrate"]')"

[ "$(claim 'd["backingStores"]["sessions"]["substrate"]')" = redis ] \
    && ok 'the second is read off the image too, and its service name says nothing: sessions holds a redis' \
    || fail "the substrate was taken from the key rather than the image: $(claim 'd["backingStores"]["sessions"]["substrate"]')"

case "$(claim 'd["backingStores"]["sessions"]["notes"][0]')" in
    *'exec-form vector'*)
        ok 'the note says why this one is refused differently: it IS a rung-1 candidate and must face the discriminator' ;;
    *)
        fail "the note collapses two different refusals into one: $(claim 'd["backingStores"]["sessions"]["notes"][0]')" ;;
esac

[ "$(claim 'd["backingStores"]["postgres"]["isolation"]["mechanism"]')" = none ] \
    && ok 'the store records mechanism none, because this repository defines no lifecycle target -- the ordinary case' \
    || fail "isolation mechanism is wrong: $(claim 'd["backingStores"]["postgres"]["isolation"]["mechanism"]')"

[ "$(claim 'd["services"]["catalog-api"]["paths"]')" = "['services/catalog-api']" ] \
    && ok "the service's paths are relative to repoRoot, so a diff in any checkout maps through them" \
    || fail "paths are wrong: $(claim 'd["services"]["catalog-api"]["paths"]')"

[ "$(claim 'd["services"]["catalog-api"]["dependsOn"]')" = "['postgres']" ] \
    && ok 'dependsOn is carried, which may only add pairs to the gate and never remove one' \
    || fail "dependsOn is wrong: $(claim 'd["services"]["catalog-api"]["dependsOn"]')"

# One spec is loopback and one is bare, so the weaker reading has to win.
[ "$(claim 'd["baseStack"]["bindsTo"]')" = 0.0.0.0 ] \
    && ok 'bindsTo takes the weaker of the two published forms: a bare mapping publishes on every interface' \
    || fail "bindsTo is wrong: $(claim 'd["baseStack"]["bindsTo"]')"

[ "$(claim 'd["portPolicy"]["reserved"]')" = "[15432, 16379, 18080]" ] \
    && ok 'every published host port is reserved, so pick-port.sh is never handed one the base stack holds' \
    || fail "reserved is wrong: $(claim 'd["portPolicy"]["reserved"]')"

# This manifest is exactly the shape a first run leaves behind when it stops at
# the port question: `reserved` is derived and needs nobody's answer, `ranges`
# is the one thing missing and is deliberately absent rather than guessed. It
# validating is what makes the stop cost one question instead of the whole
# discovery pass, every run, forever.
[ "$(claim '"ranges" in d["portPolicy"]')" = False ] \
    && ok 'the produced manifest carries no ranges at all -- a stopping run records the answer nobody gave as absent, never as a placeholder' \
    || fail "the manifest invented a ranges entry: $(claim 'd["portPolicy"].get("ranges")')"

if python3 - "$SCHEMA" "$MANIFEST" <<'PY'
import json, sys
from jsonschema import Draft202012Validator
schema = json.load(open(sys.argv[1])); doc = json.load(open(sys.argv[2]))
assert 'ranges' not in doc['portPolicy']
sys.exit(1 if list(Draft202012Validator(schema).iter_errors(doc)) else 0)
PY
then
    ok 'and it validates without ranges, so a run that stops at the port question still caches everything it discovered'
else
    fail 'a manifest with reserved and no ranges does not validate, so a stopping run has nothing valid to leave behind'
fi

# --- section 5: a drifted source is noticed ---------------------------------

printf '\n# a real topology change\n' >> "$MAIN/compose.yaml"
FP_AFTER=$(sh "$SCRIPTS/fingerprint.sh" -C "$MAIN" compose.yaml | awk '{print $1}')
[ "$FP_AFTER" != "$FP" ] \
    && ok 'an edited topology source fingerprints differently, so the slice covering it re-derives' \
    || fail 'an edited compose.yaml produced the same fingerprint, so no drift would ever be noticed'

cleanup
printf '\nresult\n'
if [ "$failures" -eq 0 ]; then
    printf '  %s check(s) ran and passed; %s skipped\n\n' "$checks" "$skips"
    exit 0
fi
printf '  %s check(s) ran; %s failed; %s skipped\n\n' "$checks" "$failures" "$skips"
exit 1
