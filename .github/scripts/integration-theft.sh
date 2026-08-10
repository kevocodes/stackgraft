#!/bin/sh
# The eighth floor: theft, which is the other half of the gate and the half no
# floor here had touched.
#
# `references/shared-state.md` opens on two hazards, not one. Contamination is
# the overlay WRITING state the base stack reads, and damage lands on the data.
# Theft is the overlay ATTACHING to a coordination primitive and taking work
# away from the base stack, and damage lands on the BEHAVIOUR of a service
# nobody modified -- which that file calls the nastier of the two, "because the
# symptom surfaces where you are not looking".
#
# Seven floors and six agent trials exercised contamination. X came back `no`
# in every one of them, so step 2 of the verdict table, `competesOn`, the
# identity proof and the whole of `references/coordination-identity.md` were
# never executed.
#
# The subject is a consumer group, because that is where the damage is directly
# observable: a message delivered to one consumer in a group is not delivered to
# another in the SAME group. Same group and the base worker goes hungry; a
# distinct group and both see everything. And it is a substrate where the
# overlay MUST attach to the base -- which is why a copy is no answer here, and
# this floor shows that too.
#
# usage: sh .github/scripts/integration-theft.sh
set -u

checks=0
failures=0
ok()   { checks=$((checks + 1)); printf '  ok    %s\n' "$1"; }
fail() { checks=$((checks + 1)); failures=$((failures + 1)); printf '  FAIL  %s\n' "$1"; }
skip() { printf '  skip  %s\n' "$1"; }

REPO=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd -P)
FIXTURE="$REPO/.github/fixtures/shopdemo"
WORK="$REPO/.sg-work-theft"
MAIN="$WORK/shopdemo"
TREE="$WORK/shopdemo-worktrees/notify"
PROJECT=sg-theft-shopdemo
STREAM=events

cleanup() {
    docker rm -fv sg-theft-overlay sg-theft-copy >/dev/null 2>&1 || true
    docker volume rm -f sg-theft-copyvol >/dev/null 2>&1 || true
    [ -d "$MAIN" ] && docker compose -p "$PROJECT" -f "$MAIN/compose.yaml" down -v >/dev/null 2>&1
    rm -rf "$WORK"
    return 0
}
trap cleanup EXIT INT TERM

printf '\ntheft: the other hazard\n\n'

if ! docker info >/dev/null 2>&1; then
    skip 'no container runtime, so the competing pair is unexercised'
    [ "${STACKGRAFT_REQUIRE_RUNTIME:-0}" = 1 ] && exit 1
    exit 0
fi

cleanup
mkdir -p "$MAIN"
cp -R "$FIXTURE/." "$MAIN/"

# A unit that ATTACHES competitively: it joins a consumer group, and the group
# name is the knob. Everything the identity proof reads is in the repository --
# the variable the service takes the name from, the value the base attaches
# under, and a route that can set it.
mkdir -p "$MAIN/services/notifier"
cat > "$MAIN/services/notifier/serve.sh" <<'SH'
#!/bin/sh
# Consumes the shared event stream as a member of a consumer group. The group
# name comes from CONSUMER_GROUP -- this variable and no other is the knob, and
# two workers under the same name split the stream between them.
set -eu
G=${CONSUMER_GROUP:?CONSUMER_GROUP is the identity this worker attaches under}
# The consumer NAME distinguishes workers inside one group; the GROUP name is
# what decides whether they compete. Two workers sharing a consumer name are
# one consumer to the broker, which is a different thing entirely.
C=${HOSTNAME:-$(hostname)}
while :; do
    # Idempotent and inside the loop: a group is destroyed with its stream, and
    # a worker that only created it at startup loops on NOGROUP forever after.
    redis-cli -h sessions XGROUP CREATE events "$G" 0 MKSTREAM >/dev/null 2>&1 || true
    out=$(redis-cli -h sessions --no-raw XREADGROUP GROUP "$G" "$C" COUNT 100 BLOCK 2000 STREAMS events '>' 2>/dev/null || true)
    n=$(printf '%s' "$out" | grep -c 'payload' 2>/dev/null || true)
    [ "${n:-0}" -gt 0 ] && redis-cli -h sessions INCRBY "consumed:$G" "$n" >/dev/null 2>&1
done
SH
chmod +x "$MAIN/services/notifier/serve.sh"
python3 - "$MAIN/compose.yaml" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
s = s.replace("  catalog-api:", """  # A competing consumer. CONSUMER_GROUP is written so a value from the calling
  # environment wins, which is the delivery route the identity proof asks for:
  # without one, a distinct identity cannot reach the overlay and the pair
  # refuses before anything starts.
  notifier:
    image: redis:7-alpine
    depends_on:
      sessions:
        condition: service_healthy
    environment:
      CONSUMER_GROUP: ${CONSUMER_GROUP:-notifier}
    volumes:
      - ./services/notifier:/app:ro
    command: ["sh", "/app/serve.sh"]

  catalog-api:""", 1)
p.write_text(s)
PY

( cd "$MAIN" && git init -q -b main && git add -A \
  && git -c user.email=f@e.com -c user.name=f commit -qm base ) >/dev/null 2>&1
git -C "$MAIN" worktree add -q -b feat/notify "$TREE" >/dev/null 2>&1
printf '\n# a change to the consumer\n' >> "$TREE/services/notifier/serve.sh"

docker compose -p "$PROJECT" -f "$MAIN/compose.yaml" up -d --wait >/dev/null 2>&1 \
    && ok 'the base stack is up, with a worker attached to the shared stream under its own group' \
    || { fail 'the base stack did not come up'; exit 1; }

SESSIONS=$(docker compose -p "$PROJECT" -f "$MAIN/compose.yaml" ps -q sessions)
IMAGE=$(docker inspect -f '{{.Config.Image}}' "$SESSIONS")
NETWORK=$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' "$SESSIONS")

# --- the four things competesOn records, all read from the repository --------

resolved=$(docker compose -p "$PROJECT" -f "$MAIN/compose.yaml" config --format json 2>/dev/null)
base_identity=$(printf '%s' "$resolved" | python3 -c 'import json,sys; print((json.load(sys.stdin)["services"]["notifier"]["environment"] or {}).get("CONSUMER_GROUP",""))' 2>/dev/null)
[ "$base_identity" = notifier ] \
    && ok "baseIdentity is read out of the base stack's own configuration, not assumed: $base_identity" \
    || fail "baseIdentity could not be read from the resolver: '$base_identity'"

grep -q 'CONSUMER_GROUP' "$MAIN/services/notifier/serve.sh" \
    && ok 'overlayIdentityEnv is the variable the service itself reads the group name from, found in its own code' \
    || fail 'the service does not read the identity from any variable, so nothing could deliver one'

grep -q 'CONSUMER_GROUP:-' "$MAIN/compose.yaml" \
    && ok 'deliveryRoute exists: the compose file lets a value from the calling environment win, so a distinct identity can reach the overlay' \
    || fail 'no route sets the identity variable, which refuses before anything starts'

# --- X = yes, and a copy is not the answer ----------------------------------

pub() { for i in 1 2 3 4 5 6; do docker exec "$SESSIONS" redis-cli XADD "$1" '*' payload "m$i" >/dev/null 2>&1; done; }
consumed() { docker exec "$SESSIONS" redis-cli GET "consumed:$1" 2>/dev/null | tr -d '\r'; }
run_overlay() {
    docker rm -fv sg-theft-overlay >/dev/null 2>&1 || true
    docker run -d --name sg-theft-overlay --network "$NETWORK" \
        --env "CONSUMER_GROUP=$1" -v "$TREE/services/notifier":/app:ro \
        "$IMAGE" sh /app/serve.sh >/dev/null 2>&1
}
settle() { _n=0; while [ "$_n" -lt 12 ]; do sleep 1; _n=$((_n + 1)); done; }

# THE DAMAGE. An overlay joining the base worker's own group takes messages the
# base worker will now never see -- and it is a service nobody modified.
docker exec "$SESSIONS" redis-cli DEL "consumed:notifier" >/dev/null 2>&1
run_overlay notifier
pub "$STREAM"
settle
same_overlay=$(consumed notifier)
docker rm -fv sg-theft-overlay >/dev/null 2>&1

# Both consumers increment the same key under a shared group, so the total is
# what the group saw; what proves the theft is that the base worker's own
# pending entries went to somebody else. Read the group's consumers instead.
# Both workers increment the same counter under a shared group, so the total is
# what the GROUP saw -- and a group sees each message once. Six published and six
# counted, with two consumers running, is the split itself: whatever the overlay
# took, the base worker did not get. Twelve would mean each saw everything, which
# is what a distinct identity buys and a shared one cannot.
shared_total=$(consumed notifier)
[ "${shared_total:-0}" = 6 ] \
    && ok "a plain attach splits the stream rather than duplicating it: six published, $shared_total counted across two consumers in one group -- the base worker did not see what the overlay took" \
    || fail "the shared-group total is $shared_total of 6, so the split this row measures did not happen"

own=$(docker exec "$SESSIONS" redis-cli XINFO CONSUMERS "$STREAM" notifier 2>/dev/null | grep -c 'name' || printf 0)
[ "${own:-0}" -ge 2 ] \
    && ok "a plain attach puts a second consumer into the base worker's own group ($own consumers under one group), which is how work is taken from a service nobody modified" \
    || fail "the overlay did not join the base group, so the hazard is not set up: $own consumer(s)"

# THE FIX. A distinct identity, and both see everything independently.
docker exec "$SESSIONS" redis-cli DEL "$STREAM" "consumed:notifier" "consumed:sg_notify" >/dev/null 2>&1
run_overlay sg_notify
pub "$STREAM"
settle
base_saw=$(consumed notifier)
overlay_saw=$(consumed sg_notify)
docker rm -fv sg-theft-overlay >/dev/null 2>&1
printf '        base group saw %s, overlay group saw %s, of 6 published\n' "${base_saw:-0}" "${overlay_saw:-0}"
[ "${base_saw:-0}" = 6 ] && [ "${overlay_saw:-0}" = 6 ] \
    && ok 'a distinct identity ends the competition: both groups see all six, and neither takes anything from the other' \
    || fail "a distinct identity did not end the competition: base $base_saw, overlay $overlay_saw of 6"

# AND A COPY ANSWERS X FOR NO SUBSTRATE. Point the overlay at a copy of the
# store instead of at a distinct identity: it competes with nothing, and it
# also exercises nothing, because the stream it was meant to read lives in the
# base. That is why a pair coordination-identity.md refuses reaches no step
# that isolates.
docker volume create sg-theft-copyvol >/dev/null 2>&1
SRC=$(docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{end}}{{end}}' "$SESSIONS")
docker run --rm -v "$SRC":/from:ro -v sg-theft-copyvol:/to "$IMAGE" \
    sh -c 'cd /from && tar cf - . | (cd /to && tar xf -)' >/dev/null 2>&1
docker run -d --name sg-theft-copy --network "$NETWORK" --network-alias sessions-copy \
    -v sg-theft-copyvol:/data "$IMAGE" redis-server --save '' --appendonly no >/dev/null 2>&1
_n=0; while [ "$_n" -lt 30 ]; do docker exec sg-theft-copy redis-cli ping >/dev/null 2>&1 && break; _n=$((_n+1)); sleep 1; done
docker exec "$SESSIONS" redis-cli DEL "$STREAM" >/dev/null 2>&1
pub "$STREAM"
settle
in_copy=$(docker exec sg-theft-copy redis-cli XLEN "$STREAM" 2>/dev/null | tr -d '\r')
in_base=$(docker exec "$SESSIONS" redis-cli XLEN "$STREAM" 2>/dev/null | tr -d '\r')
printf '        the base stream holds %s, the copy holds %s\n' "${in_base:-0}" "${in_copy:-0}"
[ "${in_base:-0}" = 6 ] && [ "${in_copy:-0}" = 0 ] \
    && ok 'a copy answers X for no substrate: an overlay pointed at one competes with nothing and exercises nothing, because the work it was meant to see is published to the base' \
    || fail "the copy is not the disconnected thing this row needs: base $in_base, copy $in_copy"

cleanup
printf '\nresult\n'
if [ "$failures" -eq 0 ]; then
    printf '  %s check(s) ran and passed\n\n' "$checks"; exit 0
fi
printf '  %s check(s) ran; %s failed\n\n' "$checks" "$failures"; exit 1
