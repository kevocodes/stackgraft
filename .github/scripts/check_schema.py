"""Schema checks for stackgraft's manifest contract.

Every positive assertion here is paired with a negative fixture that MUST be
rejected. That pairing is deliberate: an earlier version of this project's
cross-file check collected field names *from* the schema and then verified them
*against* the schema, so "missing" was structurally always empty and it passed
for several rounds while proving nothing. A check that cannot fail is not a
check, so each rule below is proven by breaking it.
"""

import copy
import json
import pathlib
import re
import sys

import jsonschema

SKILL = pathlib.Path("skills/stackgraft")
fails = []


def ok(msg):
    print(f"  ok    {msg}")


def fail(msg):
    print(f"  FAIL  {msg}")
    fails.append(msg)


schema = json.loads((SKILL / "assets/manifest.schema.json").read_text())
example = json.loads((SKILL / "assets/manifest.example.json").read_text())

try:
    jsonschema.Draft202012Validator.check_schema(schema)
    ok("schema is valid JSON Schema draft 2020-12")
except jsonschema.SchemaError as exc:
    fail(f"schema is invalid: {exc.message}")
    sys.exit(1)

validator = jsonschema.Draft202012Validator(schema)

errors = list(validator.iter_errors(example))
if errors:
    fail(f"the shipped example does not validate: {errors[0].message[:120]}")
else:
    ok("the shipped example validates")


def schema_rule(error):
    """The one rule that produced an error, as its absolute schema path.

    The last element is the validator keyword and everything before it names
    where in the schema that keyword sits, so two rules spelled with the same
    keyword - and this schema has several `required` and two `minItems` - are
    still told apart.
    """
    return "/" + "/".join(str(part) for part in error.absolute_schema_path)


def rejects(label, mutate, rule):
    """A fixture that must be rejected BY THE NAMED RULE.

    Asserting that SOME error fired is not enough, because several of these
    fixtures trip two rules at once and either one satisfies "some". "a source
    covering nothing" violates the covers minItems rule and, having emptied the
    only covering source, the contains rule that every manifest carry a source
    covering backingStores; "an empty sources array" violates sources minItems
    and that same contains rule. With only "some error" asserted, deleting the
    rule the fixture is about left its row green under the other one - the
    fixture stopped exercising anything and said so nowhere.
    """
    doc = copy.deepcopy(example)
    mutate(doc)
    errors = list(validator.iter_errors(doc))
    if not errors:
        fail(f"ACCEPTED but must be rejected: {label}")
        return
    fired = sorted({schema_rule(error) for error in errors})
    if rule in fired:
        ok(f"rejected by {rule}: {label}")
    else:
        fail(f"rejected by the wrong rule: {label} :: wanted {rule}, got {fired}")


def accepts(label, mutate):
    doc = copy.deepcopy(example)
    mutate(doc)
    errs = list(validator.iter_errors(doc))
    if errs:
        fail(f"rejected but must be accepted: {label} :: {errs[0].message[:100]}")
    else:
        ok(f"accepted: {label}")


# The isolation rules all live under one long path. Named once so the rule each
# fixture is about stays readable at its call site.
ISOLATION = "/properties/backingStores/additionalProperties/properties/isolation"

# --- the shared-state gate must not be satisfiable by declaring nothing ------
rejects(
    "a manifest with no backingStores at all",
    lambda d: d.pop("backingStores"),
    "/required",
)
rejects(
    "an empty backingStores with no root stateReview",
    lambda d: d.update(backingStores={}),
    "/allOf/0/then/required",
)
rejects(
    "a populated backingStores that no source covers",
    lambda d: d.update(
        sources=[{"path": "compose.yaml", "fingerprint": "h", "covers": ["services"]}]
    ),
    "/allOf/1/then/properties/sources/contains",
)
rejects(
    "a source covering nothing",
    lambda d: d["sources"][0].update(covers=[]),
    "/properties/sources/items/properties/covers/minItems",
)
rejects(
    "an empty sources array",
    lambda d: d.update(sources=[]),
    "/properties/sources/minItems",
)

# --- evidence must be falsifiable ------------------------------------------
rejects(
    "a classification with no fingerprint baseline",
    lambda d: d["services"]["catalog-api"]["stateReview"].pop("serviceFingerprint"),
    "/properties/services/additionalProperties/properties/stateReview/required",
)
rejects(
    "an accepted risk naming nobody",
    lambda d: [e.pop("acceptedBy", None) for e in d["acceptedRisks"].values()],
    "/properties/acceptedRisks/additionalProperties/required",
)
rejects(
    "an isolation approval with no source to measure drift against",
    lambda d: (
        d["backingStores"]["postgres"]["isolation"].update(
            approval={"at": "2026-07-31T00:00:00Z", "sourceFingerprint": "x"}
        ),
        d["backingStores"]["postgres"]["isolation"].pop("discoveredFrom"),
    ),
    f"{ISOLATION}/allOf/0/then/required",
)

# --- a mechanism must be able to do something -------------------------------
rejects(
    "an isolation mechanism with no way to apply it",
    lambda d: (
        d["backingStores"]["postgres"]["isolation"].update(mechanism="schema"),
        [
            d["backingStores"]["postgres"]["isolation"].pop(k, None)
            for k in ("command", "env")
        ],
    ),
    f"{ISOLATION}/allOf/1/then/anyOf",
)
rejects(
    "a namespace that is created and never dropped",
    lambda d: d["backingStores"]["postgres"]["isolation"].pop("teardownCommand"),
    f"{ISOLATION}/allOf/2/then/required",
)
COMPETES_ON = "/properties/services/additionalProperties/properties/competesOn/items"

# The three-part proof needs material, and a record that may omit the material is
# a record that can claim the proof without it. Each fixture below records the
# VALUE and leaves out one thing the proof reads - the same shape as an isolation
# command with no teardown, one rule along.
rejects(
    "a distinct consumer identity with no channel to the process",
    lambda d: d["services"]["search-indexer"]["competesOn"][0].update(overlayIdentity="sg-x"),
    f"{COMPETES_ON}/allOf/0/then/required",
)
rejects(
    "a distinct identity with nothing to compare it against",
    lambda d: d["services"]["search-indexer"]["competesOn"][0].update(
        overlayIdentity="sg-x",
        overlayIdentityEnv="KAFKA_GROUP_ID",
        deliveryRoute={"value": "worktree-compose", "reason": "named under the service"},
    ),
    f"{COMPETES_ON}/allOf/0/then/required",
)
rejects(
    "a distinct identity with no recorded route into the overlay's environment",
    lambda d: d["services"]["search-indexer"]["competesOn"][0].update(
        overlayIdentity="sg-x",
        overlayIdentityEnv="KAFKA_GROUP_ID",
        baseIdentity={"value": "book-indexer", "source": "the compose environment"},
    ),
    f"{COMPETES_ON}/allOf/0/then/required",
)
rejects(
    "a base value recorded with no account of where it was read",
    lambda d: d["services"]["search-indexer"]["competesOn"][0].update(
        overlayIdentity="sg-x",
        overlayIdentityEnv="KAFKA_GROUP_ID",
        baseIdentity={"value": "book-indexer"},
        deliveryRoute={"value": "worktree-compose", "reason": "named under the service"},
    ),
    f"{COMPETES_ON}/properties/baseIdentity/required",
)
rejects(
    "a delivery route this run does not recognise",
    lambda d: d["services"]["search-indexer"]["competesOn"][0].update(
        overlayIdentity="sg-x",
        overlayIdentityEnv="KAFKA_GROUP_ID",
        baseIdentity={"value": "book-indexer", "source": "the compose environment"},
        deliveryRoute={"value": "exported-shell", "reason": "the caller exported it"},
    ),
    f"{COMPETES_ON}/properties/deliveryRoute/properties/value/enum",
)

# The name family's per-store field. Absence is undetermined and must stay
# EXPRESSIBLE - a required field here would force a guess for every store that
# never needs a generated name, which is the pressure that produces one.
NAME_FORM = "/properties/backingStores/additionalProperties/properties/nameForm"
rejects(
    "a name form recorded with no account of what established it",
    lambda d: d["backingStores"]["postgres"].update(nameForm={"value": "label"}),
    f"{NAME_FORM}/required",
)
rejects(
    "a name form outside the family",
    lambda d: d["backingStores"]["postgres"].update(
        nameForm={"value": "numeric-index", "reason": "sixteen positions inside the instance"}
    ),
    f"{NAME_FORM}/properties/value/enum",
)
accepts(
    "a store recording no name form at all, which is undetermined and refuses",
    lambda d: d["backingStores"]["postgres"].pop("nameForm"),
)

# --- untrusted repository data stays constrained ----------------------------
rejects(
    "a store name carrying a shell metacharacter",
    lambda d: d["backingStores"].update({"pg;rm -rf /": d["backingStores"]["postgres"]}),
    "/properties/backingStores/propertyNames/pattern",
)
rejects(
    "a source claiming authority over the gate's own bypass",
    lambda d: d["sources"][0]["covers"].append("acceptedRisks"),
    "/properties/sources/items/properties/covers/items/not",
)

# --- schemaVersion 3, the fields it retired, and the record that replaced them
# There is no migration path and its absence is the design: everything the
# manifest holds is re-derivable, so an unrecognised version is discarded whole.
# That only works while the version itself is pinned.
#
# `writes` is rejected BY NAME rather than by additionalProperties, so the
# failure says why it is gone instead of reading as a typo.
#
# The record fixtures reach through setdefault/get so a fixture aimed at a rule
# the schema does not carry reports as rejected-by-the-wrong-rule rather than
# raising: a traceback names no missing rule.
SVC = "/properties/services/additionalProperties"
DET = f"{SVC}/properties/determinacy/additionalProperties"
MIG = f"{SVC}/properties/migrates"


def record(doc, unit="catalog-api", store="postgres"):
    return doc["services"][unit].setdefault("determinacy", {}).setdefault(store, {})


def svc(doc, unit="catalog-api"):
    return doc["services"][unit]


# Emptiness is a claim that needs evidence, and checked-and-none is the claim
# this record makes cheapest to write, so the evidence floor is one character
# rather than mere presence: an empty string is what a pass that did not look
# would leave behind.
for _label, _mutate, _rule in [
    ("a manifest still written at schemaVersion 2",
     lambda d: d.update(schemaVersion=2), "/properties/schemaVersion/const"),
    ("a service-level writes array",
     lambda d: svc(d).update(writes=["postgres"]), f"{SVC}/properties/writes/not"),
    ("a retired healthPath",
     lambda d: svc(d).update(healthPath="/health"), f"{SVC}/additionalProperties"),
    ("a retired dockerfile",
     lambda d: svc(d).update(dockerfile="Dockerfile"), f"{SVC}/additionalProperties"),
    ("the retired static kind",
     lambda d: svc(d).update(kind="static"), f"{SVC}/properties/kind/not"),
    ("a determinacy record with no fingerprint to expire it",
     lambda d: record(d).pop("serviceFingerprint", None), f"{DET}/required"),
    ("a determinacy record that answers W and leaves X unsaid",
     lambda d: record(d).pop("competes", None), f"{DET}/required"),
    ("a mutation claim carrying no evidence",
     lambda d: record(d).get("mutates", {}).pop("evidence", None),
     f"{DET}/properties/mutates/required"),
    ("checked-and-none evidenced by an empty string",
     lambda d: record(d).get("competes", {}).update(evidence=""),
     f"{DET}/properties/competes/properties/evidence/minLength"),
    ("a determinacy record on a unit that is never launched",
     lambda d: svc(d, "shared-contracts").update(determinacy={"postgres": record(d)}),
     f"{SVC}/allOf/0/then/properties"),
    ("a store recorded with no locality to decide provider eligibility from",
     lambda d: d["backingStores"]["postgres"].pop("locality"),
     "/properties/backingStores/additionalProperties/required"),
    ("migrates as the unit-level boolean it used to be",
     lambda d: svc(d).update(migrates=True), f"{MIG}/type"),
    ("a migration recorded as pointed at nothing",
     lambda d: svc(d).update(migrates={"pointing": "recorded", "stores": []}),
     f"{MIG}/properties/stores/minItems"),
    ("an unknown pointing that still names the stores it never established",
     lambda d: svc(d).update(migrates={"pointing": "unknown", "stores": ["postgres"]}),
     f"{MIG}/allOf/0/else/properties"),
]:
    rejects(_label, _mutate, _rule)

# --- and the legitimate shapes still pass -----------------------------------
accepts(
    "a store named the way real orchestrators name them",
    lambda d: d["backingStores"].update({"Postgres.main": d["backingStores"]["postgres"]}),
)
accepts(
    "a unit whose entrypoint migrates against a store nobody could name",
    lambda d: d["services"]["catalog-api"].update(migrates={"pointing": "unknown"}),
)


def storeless(doc):
    doc["backingStores"] = {}
    doc["sources"] = [
        {"path": "compose.yaml", "fingerprint": "abc", "covers": ["backingStores"]}
    ]
    doc["stateReview"] = {
        "at": "2026-07-31T00:00:00Z",
        "method": "code-scan",
        "confidence": "declared",
    }
    for entry in doc["services"].values():
        if entry.get("runnable") is not False:
            entry["dependsOn"] = []
    doc.pop("acceptedRisks", None)


accepts("a genuinely storeless repository, evidenced", storeless)


def storeless_unevidenced(doc):
    storeless(doc)
    doc["stateReview"].pop("confidence")


rejects(
    "a storeless claim with no confidence recorded",
    storeless_unevidenced,
    "/properties/stateReview/required",
)

# ...and the rule match can tell one rule from another. Without this every row
# above could be pointed at a rule no fixture ever trips and they would all
# still print ok, which is the same defect in a new place: `rejects` gained a
# way to fail, so it needs a fixture that makes it fail. Removing backingStores
# is rejected by the ROOT required rule; naming portPolicy's own required rule
# instead must not match it.
_probe = copy.deepcopy(example)
_probe.pop("backingStores")
_probe_rules = {schema_rule(error) for error in validator.iter_errors(_probe)}
if "/properties/portPolicy/required" in _probe_rules:
    fail("the rule match accepts a rule the fixture never tripped")
else:
    ok("the rule match tells one validator rule from another")

# --- a record is evidence about ONE pair, and about no other ----------------
# The schema can make a record structurally per-pair; it cannot make the READING
# per-pair. So the reading is performed here and then falsified: each fixture
# must MOVE an answer that the shipped example leaves where it is. A reading
# that quietly widened - any record on the unit standing in for the pair's own,
# a degraded record counted - would answer the same for all four rows and say so
# nowhere.
def determined(doc, unit, store):
    """W and X for one pair, from that pair's own record or not at all."""
    entry = doc["services"].get(unit, {})
    rec = entry.get("determinacy", {}).get(store)
    if rec is None or rec.get("confidence") != "declared":
        return None
    return (rec["mutates"]["value"], rec["competes"]["value"])


def reads(label, mutate, unit, store, want):
    doc = copy.deepcopy(example)
    if mutate:
        mutate(doc)
    got = determined(doc, unit, store)
    got_l = "undetermined" if got is None else f"W={got[0]} X={got[1]}"
    want_l = "undetermined" if want is None else f"W={want[0]} X={want[1]}"
    if got == want:
        ok(f"{label}: {got_l}")
    else:
        fail(f"{label}: read {got_l}, wanted {want_l}")


# The three answers the shipped example must give, then the three fixtures that
# MOVE one - so the rows above are not three spellings of "this reading never
# finds anything".
_pg = ("catalog-api", "postgres")
_ev = ("catalog-api", "events")
reads("(catalog-api, postgres) is answered by its own record", None, *_pg, (True, False))
reads("(catalog-api, events) has no record and stays", None, *_ev, None)
reads("(search-indexer, postgres) is not answered by catalog-api's record", None,
      "search-indexer", "postgres", (False, False))
reads("rejected: (catalog-api, events) once its own record is written",
      lambda d: svc(d)["determinacy"].update(events=copy.deepcopy(svc(d)["determinacy"]["postgres"])),
      *_ev, (True, False))
reads("rejected: a declared record degraded to inferred stops counting",
      lambda d: svc(d)["determinacy"]["postgres"].update(confidence="inferred"), *_pg, None)
reads("rejected: a record written for another unit answers nothing here",
      lambda d: svc(d, "storefront")["determinacy"]["postgres"].update(
          mutates={"value": True, "evidence": "planted"}), *_ev, None)

# --- the pair set's derivation is reported and reproducible -----------------
# 39 x 4 = 156 rather than 43 x 4 = 172 is only a usable regression baseline
# while the derivation behind it is stated. At example scale the same rule runs.
def derive(doc):
    units = sorted(n for n, e in doc["services"].items() if e.get("runnable") is not False)
    stores = sorted(doc["backingStores"])
    return len(units), len(stores), len(units) * len(stores)


derived = derive(example)
recorded_pairs = sum(
    len(example["services"][u].get("determinacy", {}))
    for u in example["services"]
    if example["services"][u].get("runnable") is not False
)
ok(f"the pair set derives from {derived[0]} runnable units x {derived[1]} stores = {derived[2]} pairs")

if derive(copy.deepcopy(example)) == derived:
    ok("two derivations of the same manifest report the same three counts")
else:
    fail("the derivation is not reproducible against one manifest")

_extra = copy.deepcopy(example)
_extra["services"]["ghost"] = {"runnable": False, "paths": ["p/**"], "consumers": ["catalog-api"]}
_more = copy.deepcopy(example)
_more["services"]["billing"] = copy.deepcopy(example["services"]["storefront"])

if derive(_extra) == derived:
    ok("rejected: a runnable: false unit contributes no pairs and no unit count")
else:
    fail("a non-runnable unit moved the derived counts")

if derive(_more)[2] == derived[2] + derived[1]:
    ok("rejected: the derived count moves by one store-set when a runnable unit arrives")
else:
    fail("the derivation cannot see a runnable unit arriving, so the row above proves nothing")

# The example must SHOW the partially-informed pass, not merely permit it: a
# record for one store and none at all for the next is the shape `writes` could
# not express, and an example recording every pair would document the old
# all-or-nothing world in new field names.
if 0 < recorded_pairs < derived[2]:
    ok(f"the example records {recorded_pairs} of {derived[2]} pairs, so it demonstrates the partially-informed pass")
else:
    fail(f"the example records {recorded_pairs} of {derived[2]} pairs, so it demonstrates no granularity")

_unknown = sorted(
    f"{u}::{s}"
    for u, e in example["services"].items()
    for s in e.get("determinacy", {})
    if s not in example["backingStores"]
)
if _unknown:
    fail(f"determinacy records name stores that are in no backingStores entry: {_unknown}")
else:
    ok("every determinacy record names a store the pair set was derived from")

_ghost = copy.deepcopy(example)
_ghost["services"]["catalog-api"]["determinacy"]["nosuchstore"] = record(_ghost)
if [
    s
    for e in _ghost["services"].values()
    for s in e.get("determinacy", {})
    if s not in _ghost["backingStores"]
]:
    ok("rejected: a determinacy record for a store the pair set never contained")
else:
    fail("the unknown-store row cannot fire")

# --- DS40: the diff selects units, and only a record answers stores ---------
# The gate's subject is the pairs the CHANGE can reach, built in five passes of
# which exactly ONE may narrow. The rule is written in references/shared-state.md
# and the thing that runs it is an agent reading that file; what runs here is the
# same five passes over the shipped example, so the rule's one-directionality can
# be FALSIFIED rather than asserted. A narrowing nothing executes is a narrowing
# whose safety property is a sentence.
#
# This reader is deliberately a SUBSET of the shipped escalations, and the subset
# is stated rather than left to be discovered: `migrates` and a migration in the
# diff are readable from (manifest, diff); a scheduler entrypoint and an
# externally visible side effect are read by the agent out of the commands and
# the source. Under-widening is the dangerous direction, so a reader that knows
# fewer triggers than the file must never be mistaken for the file.
MIGRATION_DIR = re.compile(r"(^|/)(migrations?|alembic|db/migrate)(/|$)")


def selects(pattern, path):
    """`dir/**` is the only form the manifest uses; any other is UNINTERPRETABLE
    and selects the unit rather than skipping it. Pass 1 may not narrow, so the
    fail-closed direction for a path matcher is to match."""
    if pattern.endswith("/**"):
        return path.startswith(pattern[:-2])
    return True


def pass1_units(doc, changed):
    """Changed paths -> units, plus the consumers of a non-runnable tree."""
    picked = set()
    for name, entry in doc["services"].items():
        if not any(selects(pat, p) for pat in entry.get("paths", []) for p in changed):
            continue
        if entry.get("runnable") is False:
            picked.update(entry.get("consumers", []))
        else:
            picked.add(name)
    return sorted(picked)


def pass2_subject(doc, units):
    """Selected runnable units x EVERY backingStores entry, unioned with the
    dependsOn names that resolve to a store - a union, so `may only ADD` is
    structural. Here they add nothing, which is the point."""
    stores = set(doc["backingStores"])
    subject = set()
    for unit in units:
        entry = doc["services"].get(unit, {})
        if entry.get("runnable") is False:
            continue
        declared = {d for d in entry.get("dependsOn", []) if d in stores}
        subject.update((unit, s) for s in stores | declared)
    return sorted(subject)


def current_fingerprint(entry):
    """Stand-in for recomputing the unit's source fingerprint: a manifest fixture
    has no tree, so the unit-level stateReview value written by the same pass
    stands in. No stateReview is nothing to compare against, which is no match."""
    return entry.get("stateReview", {}).get("serviceFingerprint")


def relieves(doc, unit, store):
    """The record that may remove EXACTLY this pair, or None. Every clause below
    is a reason to KEEP the pair, and absence is never relief."""
    entry = doc["services"].get(unit, {})
    rec = entry.get("determinacy", {}).get(store)
    if rec is None or rec.get("confidence") != "declared":
        return None
    fingerprint = current_fingerprint(entry)
    if fingerprint is None or rec.get("serviceFingerprint") != fingerprint:
        return None
    if rec["mutates"]["value"] or rec["competes"]["value"]:
        return None
    return f"{rec['method']} at {rec['at']}"


def relief_missing(clause):
    """`relieves` with exactly one clause dropped, so each clause is shown
    load-bearing on its own. Four readers rather than one lax one, because "some
    worse reader exists" proves no particular clause is carrying anything."""

    def variant(doc, unit, store):
        entry = doc["services"].get(unit, {})
        records = entry.get("determinacy", {})
        rec = records.get(store)
        if rec is None and clause == "this pair":
            rec = next(iter(records.values()), None)     # any record on the unit
        if rec is None:
            return None
        if clause != "declared" and rec.get("confidence") != "declared":
            return None
        if clause != "fingerprint" and rec.get("serviceFingerprint") != current_fingerprint(entry):
            return None
        if clause != "reaches" and (rec["mutates"]["value"] or rec["competes"]["value"]):
            return None
        return "a record exists"

    return variant


def pass4_triggers(doc, unit, changed):
    """Escalations, which read the launched process rather than the diff."""
    entry = doc["services"].get(unit, {})
    stores = sorted(doc["backingStores"])
    out = []
    migrates = entry.get("migrates") or {}
    if migrates.get("pointing") == "recorded":
        out.append((sorted(migrates.get("stores", [])), "migrates names this store"))
    elif migrates.get("pointing") == "unknown":
        out.append((stores, "migrates is pointed somewhere unrecorded"))
    mine = [p for p in changed if any(selects(pat, p) for pat in entry.get("paths", []))]
    if any(MIGRATION_DIR.search(p) for p in mine):
        out.append((stores, "the diff touches a migrations directory"))
    return out


def isolates(doc, store):
    """N: a mechanism with no way to apply it IS none."""
    iso = doc["backingStores"][store].get("isolation", {})
    if iso.get("mechanism") in (None, "none"):
        return False
    return bool(iso.get("command") or iso.get("env"))


def booleans(doc, unit, store):
    """W and X for one pair; None is undetermined, which is not False."""
    entry = doc["services"].get(unit, {})
    migrates = entry.get("migrates") or {}
    if migrates.get("pointing") == "unknown":
        return None, None
    rec = entry.get("determinacy", {}).get(store)
    fresh = (
        rec is not None
        and rec.get("confidence") == "declared"
        and rec.get("serviceFingerprint") == current_fingerprint(entry)
    )
    # `migrates` is read BEFORE the record and a checked-and-none `mutates`
    # never cancels it.
    if store in (migrates.get("stores") or []):
        w = True
    else:
        w = rec["mutates"]["value"] if fresh else None
    return w, (rec["competes"]["value"] if fresh else None)


SHARED_MD = SKILL / "references/shared-state.md"
VERDICT_HEADING = "## The verdict"
VERDICT_TOKEN = re.compile(r"\*\*(REFUSE|REUSE|ISOLATE)\b")
STEP_POINTER = re.compile(r"\bstep (\d+)\b")


def step_table(text=None):
    """The shipped step table, parsed OUT OF references/shared-state.md.

    This reader used to restate the table in Python - `if x: return "REFUSE"` -
    and that is how a defect survived seven slices. At 1.1.0 step 5 read
    "**REFUSE**, or run a dedicated store", so step 2 sending an X-refused pair
    there was safe; slice 4a redefined step 5 as "**ISOLATE by a seeded copy**"
    and the pointer in step 2 was never revisited. The suite could not see it
    because nothing here or in verify.sh read the table's ACTION cells: a
    correct reader modelling a procedure the shipped file no longer stated.

    So the actions come from the file. `verdicts` is the ordered list of verdict
    tokens the action cell states - step 5 states two, the copy and the refusal
    where no provider is recorded - and `points_at` is every step that cell
    hands a pair on to, which is the pointer whose destination moved.
    """
    rows, inside = {}, False
    for line in (text if text is not None else SHARED_MD.read_text()).splitlines():
        if line.startswith("## "):
            inside = line.strip() == VERDICT_HEADING
            continue
        if not inside or not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) != 3 or not cells[0].isdigit():
            continue
        rows[int(cells[0])] = {
            "condition": cells[1].replace("*", ""),
            "verdicts": VERDICT_TOKEN.findall(cells[2]),
            "points_at": sorted({int(n) for n in STEP_POINTER.findall(cells[2])}),
        }
    return rows


STEPS = step_table()


def step_for(steps, pattern):
    """The step whose CONDITION matches, never a number carried here.

    A reader holding `2` would be the same live pointer this whole repair is
    about, one file along: renumber the table and it reads the wrong cell while
    every row below stays green.
    """
    for number, row in sorted(steps.items()):
        if re.search(pattern, row["condition"]):
            return number
    return None


UNDETERMINED = step_for(STEPS, r"of W, X, N undetermined")
COMPETES = step_for(STEPS, r"X = yes")
NEITHER = step_for(STEPS, r"X = no, W = no")
IN_INSTANCE = step_for(STEPS, r"N = yes")
BY_COPY = step_for(STEPS, r"N = no")


def step_outcome(step, where_not=False):
    """What that step hands the pair, out of its own action cell.

    `where_not` takes the SECOND verdict the cell states, which is how step 5
    says "a copy where the store records a usable provider, a refusal where it
    does not". A cell stating one verdict has no second reading, and a step that
    read as nothing at all answers UNREAD so every row below goes red rather
    than passing over a table this reader never opened.
    """
    tokens = STEPS.get(step, {}).get("verdicts", [])
    if not tokens:
        return "UNREAD"
    if where_not:
        return tokens[1] if len(tokens) > 1 else "UNREAD"
    return tokens[0]


def has_provider(doc, store):
    """Step 5's own condition: does this store record a USABLE provider.

    Present and `declared`, which is the bar the isolation record beside it is
    held to. What this deliberately does NOT model is a provider whose runtime
    is unbuilt: `references/isolation-providers.md` refuses those by name inside
    the provider, downstream of this table, and no fixture here carries one - a
    clause no input ever reaches is a clause that certifies itself.
    """
    provider = (doc["backingStores"][store].get("isolation") or {}).get("provider") or {}
    return provider.get("confidence") == "declared"


def verdict(doc, unit, store):
    """The shipped step table, in order, stopping at the first match.

    The CONDITIONS are modelled here - they are what is under test. The ACTIONS
    are read out of the shipped table, so a step whose verdict is rewritten
    moves this reader with it instead of leaving it certifying the old one.
    """
    w, x = booleans(doc, unit, store)
    if w is None or x is None:
        return step_outcome(UNDETERMINED)
    if x:
        return step_outcome(COMPETES)
    if not w:
        return step_outcome(NEITHER)
    if isolates(doc, store):
        return step_outcome(IN_INSTANCE)
    return step_outcome(BY_COPY, where_not=not has_provider(doc, store))


def copies_offered_for_x(steps):
    """Steps the X refusal hands a pair on to whose OWN action isolates.

    SSS-A2 and CI-1 read over the shipped table: a pair carrying X and not W
    must not cause a store copy to be provisioned, and no reference may offer a
    copy as a remedy for X alone. So the step that refuses X may point at no
    step whose action is a copy. This is the row the injected sentence below
    turns red, and the row that would have caught the shipped defect.
    """
    competes = step_for(steps, r"X = yes")
    if competes is None:
        return ["the table states no X = yes step at all"]
    offered = []
    for number in steps[competes]["points_at"]:
        if number == competes:
            continue
        action = steps.get(number, {}).get("verdicts") or ["UNREAD"]
        if action[0] != "REFUSE":
            offered.append(f"step {number} ({action[0]})")
    return offered


if sorted(STEPS) == [1, 2, 3, 4, 5] and all(row["verdicts"] for row in STEPS.values()):
    ok(
        "the step table parses out of shared-state.md: "
        + ", ".join(f"{n}->{'/'.join(STEPS[n]['verdicts'])}" for n in sorted(STEPS))
    )
else:
    fail(f"the step table did not read as five steps each stating a verdict: {STEPS}")

if [UNDETERMINED, COMPETES, NEITHER, IN_INSTANCE, BY_COPY] == [1, 2, 3, 4, 5]:
    ok("each step is found by its own condition cell, so a renumbered table moves the reader with it")
else:
    fail(
        "a condition cell no longer selects its step: "
        f"undetermined={UNDETERMINED}, X={COMPETES}, neither={NEITHER}, "
        f"in-instance={IN_INSTANCE}, copy={BY_COPY}"
    )

_offered = copies_offered_for_x(STEPS)
if not _offered:
    ok("the X refusal hands a pair to no step that isolates: a copy is never offered as a remedy for X")
else:
    fail(f"step {COMPETES} routes an X-refused pair to {_offered}, which provisions a copy for a hazard no copy ends")

# The regression case, and it is the EXACT sentence an adversarial verification
# proved invisible: with it in place the suite ran 747 ok / 0 FAIL / exit 0,
# byte-identical to clean, because nothing read the table's action cells.
SHIPPED_X_TAIL = (
    "A copy answers X for no substrate, so a pair that file refuses "
    "— a shared queue, a lock, a replication slot, a scheduler singleton — "
    "**is refused here and reaches no step that isolates.**"
)
INJECTED_X_TAIL = (
    "A copy answers X on every substrate, and pairs that file refuses "
    "— a shared queue, a lock, a replication slot, a scheduler singleton — "
    "are answered by a seeded copy of the store at step 5."
)
_clean_text = SHARED_MD.read_text()
_injected_text = _clean_text.replace(SHIPPED_X_TAIL, INJECTED_X_TAIL)
if _injected_text == _clean_text:
    fail("the injection landed nowhere, so the row below tests the shipped file rather than the defect")
elif copies_offered_for_x(step_table(_injected_text)):
    ok("rejected: step 2 routing an X-refused pair to step 5, whose action is a seeded copy")
else:
    fail("the injected sentence changed nothing: the pointer row cannot see an X pair handed to a copy")

# ...and each outcome is proved to come OUT OF THE CELL by rewriting the cell and
# showing the reader follow it. Without these two, `verdict` restating the table
# again would pass every row above.
_x_flipped = step_table(_clean_text.replace(
    "| 2 | **X = yes**, whatever W and N say | **REFUSE** a plain attach.",
    "| 2 | **X = yes**, whatever W and N say | **ISOLATE** a plain attach.",
))
if _x_flipped.get(2, {}).get("verdicts", [None])[0] == "ISOLATE":
    ok("rejected: a step-2 action cell rewritten to ISOLATE - the reader takes X's outcome from the cell, not from Python")
else:
    fail("rewriting step 2's action changed nothing the reader reads, so its outcome is still restated here")

_copy_dropped = step_table(_clean_text.replace(
    "| 5 | X = no, **W = yes**, N = no | **ISOLATE by a seeded copy** where the store records a usable provider",
    "| 5 | X = no, **W = yes**, N = no | **REFUSE** where the store records a usable provider",
))
if _copy_dropped.get(5, {}).get("verdicts", [None])[0] == "REFUSE":
    ok("rejected: a step-5 action cell put back to 1.1.0's refusal - the reader takes the copy's outcome from the cell too")
else:
    fail("rewriting step 5's action changed nothing the reader reads, so its outcome is still restated here")


def gate(doc, changed, relief=relieves):
    """The five passes, in order, reporting what each one did."""
    units = pass1_units(doc, changed)
    subject = pass2_subject(doc, units)
    removed = [(pair, relief(doc, *pair)) for pair in subject]
    removed = [(pair, why) for pair, why in removed if why]
    gated = set(subject) - {pair for pair, _ in removed}
    reinserted = []
    for unit in units:
        for stores, trigger in pass4_triggers(doc, unit, changed):
            for store in stores:
                if (unit, store) in subject and (unit, store) not in gated:
                    gated.add((unit, store))
                    reinserted.append(((unit, store), trigger))
    return {
        "derived": derive(doc),
        "selected": units,
        "subject": subject,
        "removed": removed,
        "reinserted": sorted(reinserted),
        "gated": sorted(gated),
    }


def render(report, overwrite=False):
    """What the run prints.

    `overwrite=True` is the report this rule forbids - the narrowed count written
    into the derived count's place, which reads as a smaller repository rather
    than as a narrowed subject. It is a second RENDERER and not a string edited
    afterwards: a negative built by replacing the number in the good report's
    output tests str.replace and nothing else.
    """
    units, stores, pairs = report["derived"]
    shown = len(report["gated"]) if overwrite else pairs
    lines = [f"derived: {units} runnable units x {stores} stores = {shown} pairs"]
    lines.append("selected by the diff: " + (", ".join(report["selected"]) or "none"))
    lines += [f"removed: {u}::{s} on its own record, {why}" for (u, s), why in report["removed"]]
    lines += [f"re-inserted: {u}::{s} by {why}" for (u, s), why in report["reinserted"]]
    lines.append(f"gated: {len(report['gated'])} pairs, beside the derived {shown}")
    return "\n".join(lines)


def reports_both_counts(text, report):
    """Both counts, labelled, with the derived one still saying what was derived."""
    derived = report["derived"][2]
    return f"= {derived} pairs" in text and f"beside the derived {derived}" in text


FRONTEND = ["apps/storefront/src/App.tsx"]
BACKEND = ["services/catalog/src/books.py"]


def with_migrates(pointing, stores=None, unit="storefront"):
    doc = copy.deepcopy(example)
    doc["services"][unit]["migrates"] = (
        {"pointing": pointing, "stores": stores} if stores else {"pointing": pointing}
    )
    return doc


# A frontend-only diff against a multi-store repository gates nothing, and names
# every pair it removed with the record that removed it.
_front = gate(example, FRONTEND)
if _front["selected"] == ["storefront"] and not _front["gated"]:
    ok(f"a frontend-only diff gates 0 of {_front['derived'][2]} derived pairs")
else:
    fail(f"a frontend-only diff gated {len(_front['gated'])} pair(s): {_front['gated']}")

if len(_front["removed"]) == len(_front["subject"]) and all(why for _, why in _front["removed"]):
    ok("every removed pair is named with the record that removed it")
else:
    fail("a pair left the subject without the record that removed it being named")

# ONE-DIRECTIONAL, as an invariant over every fixture rather than as a sentence:
# a pair may only be removed if it would have classified REUSE anyway, and no
# surviving pair's verdict may differ from the verdict it has with no narrowing
# at all. Removing anything else is confidence the diff did not earn.
def one_directional(doc, changed, relief=relieves):
    report = gate(doc, changed, relief)
    for pair, _ in report["removed"]:
        if pair in report["gated"]:
            continue                       # returned by pass 4; it narrowed nothing
        if verdict(doc, *pair) != "REUSE":
            return f"{pair[0]}::{pair[1]} was removed while classifying {verdict(doc, *pair)}"
    return None


_degraded = copy.deepcopy(example)
_degraded["services"]["storefront"]["determinacy"]["kafka"].update(confidence="inferred")
_drifted = copy.deepcopy(example)
_drifted["services"]["storefront"]["determinacy"]["postgres"].update(serviceFingerprint="0" * 40)
_orphaned = copy.deepcopy(example)
_orphaned["services"]["storefront"]["determinacy"].pop("events")

# The last three manifests are here because of a measurement: with only the
# first five, deleting the fingerprint clause from `relieves` outright left this
# row GREEN - every record in the shipped example is fresh, so the clause was
# never reached and the invariant was reporting on a reader it never exercised.
# A case list that cannot present a clause with the input that clause is for is
# a case list that certifies the clause by never using it.
CASES = [
    ("a frontend-only diff", example, FRONTEND),
    ("a backend diff against the migrating unit", example, BACKEND),
    ("a frontend diff against a unit recorded as migrating", with_migrates("recorded", ["postgres"]), FRONTEND),
    ("a frontend diff against an unscoped migration", with_migrates("unknown"), FRONTEND),
    ("a migrations directory in the diff", example, ["apps/storefront/migrations/003.sql"]),
    ("a degraded record on a selected unit", _degraded, FRONTEND),
    ("a drifted record on a selected unit", _drifted, FRONTEND),
    ("a pair whose record was never written", _orphaned, FRONTEND),
]
_broken = [label for label, doc, changed in CASES if one_directional(doc, changed)]
if _broken:
    fail(f"the narrowing removed a pair that does not classify REUSE: {_broken}")
else:
    ok(f"the narrowing only ever removes pairs that classify REUSE ({len(CASES)} cases)")

# ...and that invariant must be able to fail once per clause, or it is five
# spellings of a reader that removes nothing. Each row drops ONE clause of
# `relieves` and names the manifest on which that clause is what was holding the
# pair - so a clause quietly deleted later has a row that goes red rather than a
# comment that goes stale.
for _clause, _doc, _changed, _why in [
    ("declared", _degraded, FRONTEND, "an inferred record relieves a pair that refuses"),
    ("fingerprint", _drifted, FRONTEND, "a drifted record relieves a pair that refuses"),
    ("reaches", example, BACKEND, "a record recording a write relieves the pair it describes"),
    ("this pair", _orphaned, FRONTEND, "a sibling's record answers a pair nobody examined"),
]:
    _broke = one_directional(_doc, _changed, relief_missing(_clause))
    if _broke:
        ok(f"rejected: dropping the {_clause} clause - {_why} ({_broke})")
    else:
        fail(f"the {_clause} clause is not load-bearing: dropping it narrowed nothing extra")

# The limit, not the relief: a change confined to a unit's frontend does not
# make that unit stateless. Pass 4 runs after pass 3 and outranks it.
_mig = gate(with_migrates("recorded", ["postgres"]), FRONTEND)
_mig_pairs = [pair for pair, _ in _mig["reinserted"]]
if _mig_pairs == [("storefront", "postgres")] and booleans(
    with_migrates("recorded", ["postgres"]), "storefront", "postgres"
)[0] is True:
    ok("re-inserted by migrates with W=yes: storefront::postgres, and the trigger is named")
else:
    fail(f"a frontend diff relieved a unit whose entrypoint migrates: {_mig_pairs}")

if all(pair in [p for p, _ in _mig["removed"]] for pair in _mig_pairs):
    ok("the run names both events: removed in pass 3, returned in pass 4")
else:
    fail("a pair returned in pass 4 without pass 3 having named it removed")

# An unscoped migration cannot be laundered into relief by a small diff.
_unscoped = gate(with_migrates("unknown"), FRONTEND)
_unscoped_verdicts = {verdict(with_migrates("unknown"), *p) for p in _unscoped["gated"]}
if len(_unscoped["gated"]) == 3 and _unscoped_verdicts == {"REFUSE"}:
    ok("rejected: an unscoped migrates keeps every store of that unit, all refusing")
else:
    fail(f"an unscoped migrates was narrowed by a small diff: {_unscoped['gated']}")


def stays(label, mutate, unit, store, want="REFUSE"):
    """A pair the narrowing must NOT remove, and whose verdict it must not soften.

    `want` is per case because 2.0 moved one of them. A pair carrying W with no
    in-instance mechanism is answered by a seeded copy now rather than refused -
    shared-state.md's own "half a lifecycle now selects the copy rather than a
    refusal" - so demanding REFUSE of all five would be 1.1.0's step 5 restated
    at a second call site, which is the defect this file just took out of
    `verdict`.
    """
    doc = copy.deepcopy(example)
    mutate(doc)
    report = gate(doc, FRONTEND)
    got = verdict(doc, unit, store)
    if (unit, store) in report["gated"] and got == want:
        ok(f"rejected: {label} - {unit}::{store} stays in the subject and answers {got}")
    else:
        fail(f"{label}: {unit}::{store} left the subject, or answered {got} rather than {want}")


# The first case is two readings of one mutation and both must hold: with
# storefront's own events record gone, neither its SIBLING records nor
# search-indexer's declared record for the same store may answer that pair.
stays("a narrowing with no record for that pair, and none on a sibling or another unit",
      lambda d: d["services"]["storefront"]["determinacy"].pop("events"), "storefront", "events")
stays("a relieving record whose serviceFingerprint has drifted",
      lambda d: d["services"]["storefront"]["determinacy"]["postgres"].update(
          serviceFingerprint="0" * 40), "storefront", "postgres")
stays("a relieving record degraded to inferred",
      lambda d: d["services"]["storefront"]["determinacy"]["kafka"].update(
          confidence="inferred"), "storefront", "kafka")
stays("a record that says the changed code DOES reach the store",
      lambda d: d["services"]["storefront"]["determinacy"]["events"]["mutates"].update(
          value=True), "storefront", "events", want="ISOLATE")
stays("a record recording a competitive attachment",
      lambda d: d["services"]["storefront"]["determinacy"]["kafka"]["competes"].update(
          value=True), "storefront", "kafka")

# ...and the narrowing must still be able to relieve, or every row above is
# satisfied by a reader that removes nothing at all.
if len(gate(example, FRONTEND)["removed"]) == 3:
    ok("the narrowing does relieve: all three of the frontend unit's pairs leave on their own records")
else:
    fail("nothing was ever relieved, so the rows above pass over a gate that narrows nothing")

# A survivor is not strengthened by a small diff: the degraded record still does
# not count, and its verdict is the one it has with no narrowing at all.
if verdict(_degraded, "storefront", "kafka") == "REFUSE" and booleans(
    _degraded, "storefront", "kafka"
) == (None, None):
    ok("a survivor of the narrowing is undetermined exactly as it would be with no narrowing")
else:
    fail("a surviving pair was read as better evidenced because the diff was small")

# `dependsOn` still narrows nothing: the subject is identical whether the unit
# declares one store, all of them, or none.
_empty = copy.deepcopy(example)
_empty["services"]["storefront"]["dependsOn"] = []
if pass2_subject(_empty, ["storefront"]) == pass2_subject(example, ["storefront"]):
    ok("rejected: dependsOn: [] removes no pair - every backingStores entry still yields one")
else:
    fail("dependsOn narrowed the subject, which is the rule this change does not repeal")

_declaring = copy.deepcopy(example)
_declaring["services"]["storefront"]["dependsOn"] = ["postgres", "events", "kafka"]
if len(pass2_subject(_declaring, ["storefront"])) == len(pass2_subject(_empty, ["storefront"])):
    ok("the laziest manifest yields the same subject as the fullest one")
else:
    fail("declaring more stores changed the subject, so dependsOn is being read as evidence")

# V67's second half: the gated count appears BESIDE the derived one. Nothing
# narrowed until this slice, so the rule had no executable check until now. The
# fixture must ACTUALLY narrow, or `beside` is satisfied by one number printed
# twice and the row would pass on a run that reported a single count.
_derived_n, _gated_n = _front["derived"][2], len(_front["gated"])
if _derived_n == _gated_n:
    fail(f"the counts fixture narrows nothing ({_derived_n} = {_gated_n}), so `beside` proves nothing")
elif reports_both_counts(render(_front), _front):
    ok(f"the run reports the gated {_gated_n} beside the derived {_derived_n}, not in place of it")
else:
    fail(f"the report does not carry both counts: {render(_front)!r}")

if not reports_both_counts(render(_front, overwrite=True), _front):
    ok("rejected: a report that writes the narrowed count into the derived count's place")
else:
    fail("the both-counts row cannot see the derived count being overwritten")

# --- D4: X resolves by a distinct identity, and never by a copy -------------
# The rule is three properties of a READING, exactly as the narrowing above is,
# so a grep over the prose cannot falsify any of them: whether a pair that needs
# only a name creates nothing, whether each leg of the proof is load-bearing on
# its own, and whether a copy can be mistaken for an answer to X. What runs here
# is that reading over the shipped example.
#
# One thing is modelled rather than shipped, and it is named rather than left to
# be discovered: the copy itself belongs to the data hazard's provider, which is
# a later slice. What the reader models is what the RULE says the W half buys - a
# runtime object - because without it "an X-only pair provisions nothing" is
# satisfied by a reader in which nothing ever provisions at all.
IDENTITY_MD = SKILL / "references/coordination-identity.md"
KNOB_HEADING = "## What is this substrate's identity knob"


def knob_table(text=None):
    """{knob: does a distinct value end the competition}, read out of the file.

    Parsed rather than restated here. A reader carrying its own copy of the
    table would certify a file it never opened, and the substrate confirmation
    is the one leg of the proof that lives in prose rather than in a manifest.
    """
    rows, inside = {}, False
    for line in (text if text is not None else IDENTITY_MD.read_text()).splitlines():
        if line.startswith("## "):
            inside = line.strip() == KNOB_HEADING
            continue
        if not inside or not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) != 3 or cells[0].startswith("Coordination") or set(cells[0]) <= set("- "):
            continue
        token = re.search(r"`([^`]+)`", cells[1])
        if token:
            # Anything that is not an unconditional Yes is unconfirmed. The
            # fail-closed direction for "does a name help here" is that it does
            # not, and verify.sh rejects an answer this cannot parse rather than
            # letting it become a refusal for the wrong reason.
            rows[token.group(1)] = cells[2].startswith("**Yes**")
    return rows


KNOBS = knob_table()

if len(KNOBS) >= 6 and any(KNOBS.values()) and not all(KNOBS.values()):
    ok(f"the knob table reads: {sum(KNOBS.values())} of {len(KNOBS)} knobs end the competition")
else:
    fail(f"the knob table read as {KNOBS}, which cannot both confirm and refuse")


def identity_proof(doc, unit, store, applied=True):
    """None when the identity is proven; otherwise why it is not.

    Distinct, delivered, substrate-confirmed - and any one unproven leaves X
    undetermined rather than still yes, which is what makes the loop terminate
    on evidence instead of on another attempt.
    """
    entry = doc["services"].get(unit, {})
    rec = next((c for c in entry.get("competesOn", []) if c.get("store") == store), None)
    if rec is None or "overlayIdentity" not in rec:
        return "no distinct identity is recorded"
    base = (rec.get("baseIdentity") or {}).get("value")
    if not base:
        return "the base stack's own value could not be read, so nothing was compared"
    if rec["overlayIdentity"] == base:
        return "the recorded value equals the value the base stack attaches under"
    if not rec.get("overlayIdentityEnv"):
        return "no variable of the service's own carries the value"
    if (rec.get("deliveryRoute") or {}).get("value") in (None, "none"):
        return "no route sets that variable in the overlay's environment"
    if not applied:
        return "the launch completed without applying the recorded variable"
    knob = rec.get("identity")
    if knob not in KNOBS:
        return f"the substrate table covers no knob named {knob!r}"
    if not KNOBS[knob]:
        return f"no distinct value ends the competition on {knob!r}"
    return None


def resolve(doc, unit, store, applied=True):
    """What resolving one pair does, and what it creates while doing it."""
    w, x = booleans(doc, unit, store)
    unproven = identity_proof(doc, unit, store, applied) if x else None
    by_identity = bool(x) and unproven is None
    if x:
        x = False if by_identity else None
    if w is None or x is None:
        return {"verdict": "REFUSE", "mechanisms": [], "provisions": [], "unproven": unproven}
    mechanisms = ["identity"] if by_identity else []
    provisions = []
    if w:
        mechanisms.append("copy")
        provisions = [f"volume:{store}", f"instance:{store}"]
    return {
        "verdict": "ISOLATE" if w else ("REUSE" if not by_identity else "REUSE"),
        "mechanisms": mechanisms,
        "provisions": provisions,
        "unproven": None,
    }


PROVEN = {
    "store": "kafka",
    "identity": "group.id",
    "overlayIdentity": "sg_feat_x_1a2b3c4d",
    "overlayIdentityEnv": "KAFKA_GROUP_ID",
    "baseIdentity": {"value": "book-indexer", "source": "the compose service's own environment"},
    "deliveryRoute": {"value": "worktree-compose", "reason": "the worktree compose file names it under search-indexer"},
}


def paired(writes=False, **over):
    """search-indexer::kafka, the shipped X-only pair, with its identity recorded."""
    doc = copy.deepcopy(example)
    entry = dict(PROVEN)
    for key, value in over.items():
        if value is None:
            entry.pop(key, None)
        else:
            entry[key] = value
    doc["services"]["search-indexer"]["competesOn"] = [entry]
    if writes:
        doc["services"]["search-indexer"]["determinacy"]["kafka"]["mutates"]["value"] = True
    return doc


# An X-only pair is answered by a name and creates nothing.
_x_only = resolve(paired(), "search-indexer", "kafka")
if _x_only["mechanisms"] == ["identity"] and _x_only["provisions"] == []:
    ok("a pair carrying X and not W is resolved by identity and leaves the runtime inventory unchanged")
else:
    fail(f"an X-only pair resolved as {_x_only}")

# ...and the inventory row must be able to SEE a provision, or it passes because
# nothing in the fixture ever provisions anything.
_both = resolve(paired(writes=True), "search-indexer", "kafka")
if _both["mechanisms"] == ["identity", "copy"] and _both["provisions"]:
    ok(f"a pair carrying X and W takes both mechanisms and provisions {len(_both['provisions'])} runtime object(s)")
else:
    fail(f"a W-and-X pair resolved as {_both}, so the inventory row cannot see a provision")

# The copy is not an answer to X. With the identity unrecorded the same writing
# pair refuses, and provisions nothing while refusing.
_copy_only = resolve(paired(writes=True, overlayIdentity=None), "search-indexer", "kafka")
if _copy_only["verdict"] == "REFUSE" and _copy_only["provisions"] == []:
    ok("rejected: a copy offered for a pair that also carries X - X stays undetermined and the pair refuses")
else:
    fail(f"a copy answered X on its own: {_copy_only}")

# Each leg of the proof, failing on its own. Four readers of one rule would be
# four spellings of a reader that proves nothing; each row here names the leg and
# the pair must refuse for THAT reason.
for _label, _doc, _applied, _want in [
    ("the value equals the base stack's",
     paired(overlayIdentity="book-indexer"), True, "equals the value the base stack"),
    ("the base stack's value could not be read",
     paired(baseIdentity={"value": "", "source": "the resolver was unavailable"}), True, "could not be read"),
    ("no route carries the variable into the overlay",
     paired(deliveryRoute={"value": "none", "reason": "the run form passes no environment"}), True, "no route sets"),
    ("the identity was recorded and never applied",
     paired(), False, "without applying the recorded variable"),
    ("a knob the substrate table does not cover",
     paired(identity="scheduler-slot"), True, "covers no knob"),
    ("a knob the table answers No to - a queue the base stack already consumes",
     paired(identity="queue"), True, "ends the competition"),
]:
    _got = resolve(_doc, "search-indexer", "kafka", _applied)
    if _got["verdict"] != "REFUSE" or _got["mechanisms"]:
        fail(f"{_label}: the pair resolved anyway as {_got}")
    elif _want in (_got["unproven"] or ""):
        ok(f"rejected: {_label} ({_got['unproven']})")
    else:
        fail(f"{_label}: refused for the wrong reason - {_got['unproven']}")

# ...and the proven case must actually pass, or every row above is satisfied by a
# reader that refuses everything put in front of it.
if identity_proof(paired(), "search-indexer", "kafka") is None:
    ok("the identity proof does clear a pair: distinct, delivered and substrate-confirmed")
else:
    fail("no pair can ever satisfy the proof, so the six refusals above prove nothing")

# The whole verdict still comes from shared-state.md: a re-classified X follows W.
if verdict(example, "search-indexer", "kafka") == "REFUSE" and resolve(paired(), "search-indexer", "kafka")["verdict"] == "REUSE":
    ok("the shipped pair refuses with no identity recorded, and follows W once one is proven")
else:
    fail("recording an identity did not change the verdict, or changed it without the proof")

# ...and the substrate leg is read OUT OF THE FILE rather than known. Flip the
# one row the shipped fixture depends on and the same proof must stop clearing:
# without this row, a reader that had quietly hard-coded "group.id is fine" would
# pass every row above while the shipped table said the opposite.
_flipped = KNOBS.copy()
KNOBS = knob_table(
    IDENTITY_MD.read_text().replace(
        "| Kafka consumer group | `group.id` | **Yes**",
        "| Kafka consumer group | `group.id` | **No**",
    )
)
if KNOBS.get("group.id") is False and identity_proof(paired(), "search-indexer", "kafka"):
    ok("rejected: a knob table answering No for group.id - the same proven pair stops clearing")
else:
    fail("the substrate leg does not come from the shipped table; flipping its answer changed nothing")
KNOBS = _flipped


# --- every field the documents name must exist ------------------------------
names = set()


def walk(node):
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "properties" and isinstance(value, dict):
                names.update(value)
            walk(value)
    elif isinstance(node, list):
        for item in node:
            walk(item)


walk(schema)

prose = " ".join(
    p.read_text() for p in [SKILL / "SKILL.md", *sorted((SKILL / "references").glob("*.md"))]
)

# Keys that belong to somebody else's format, plus one local variable name.
# Listed individually and on purpose: a blanket pattern here would make the
# check unable to fail, which is the exact defect this file was written to
# avoid. Adding to this set should require justifying each entry.
FOREIGN = {
    "appPort",            # devcontainer.json
    "forwardPorts",       # devcontainer.json
    "runServices",        # devcontainer.json
    "dockerComposeFile",  # devcontainer.json
    "applicationUrl",     # launchSettings.json, .NET
    "gitCommonDir",       # a variable in SKILL.md step 1, not a manifest field
}

# camelCase tokens inside backticks are field references; anything else is prose.
referenced = {
    t
    for t in re.findall(r"`([a-z][A-Za-z0-9]*)`", prose)
    if re.search(r"[A-Z]", t)
} - FOREIGN
# The comparison is only worth its sentence while there is something in it.
# Prose carrying no backticked camelCase at all - a rewrite that dropped the
# backticks, a references directory that stopped being read - gives an empty
# `referenced`, so `missing` is empty too and the row printed ok while covering
# nothing. That is a gate satisfied by absence, which is the same defect this
# file was written against, in a new place.
#
# A floor rather than an exact count, for the same reason verify.sh takes
# `notes_n >= 2` on the CHANGELOG sections and a floor on the body's skill
# pointers: enough to say the set is really there, never a number that a
# legitimate edit to the prose would break.
REFERENCED_FLOOR = 20

def referenced_in(text):
    return {t for t in re.findall(r"`([a-z][A-Za-z0-9]*)`", text) if re.search(r"[A-Z]", t)} - FOREIGN


missing = sorted(referenced - names)
if len(referenced) < REFERENCED_FLOOR:
    fail(
        f"the documents name only {len(referenced)} backticked field(s), under the "
        f"floor of {REFERENCED_FLOOR}: the cross-check is covering nothing"
    )
elif missing:
    fail(f"documents name fields absent from the schema: {missing}")
else:
    ok(f"every field the documents name exists in the schema ({len(referenced)} checked)")

# The check above can only fail if it is actually comparing two different sets.
# Prove that before trusting it.
if "definitelyNotAField" in names:
    fail("the field cross-check is comparing a set against itself")
else:
    ok("the field cross-check is capable of failing")

# ...and it must be able to fail ON THE NEW FILE specifically. The self-test
# above proves the two sets differ; it does not prove this file is one of the
# ones being read, and a references directory that stopped being globbed would
# leave both rows green. So the fixture is that file's own text plus one
# camelCase token that is not a manifest field.
_new_prose = IDENTITY_MD.read_text()
if referenced_in(_new_prose) - names:
    fail(f"coordination-identity.md names fields absent from the schema: {sorted(referenced_in(_new_prose) - names)}")
elif referenced_in(_new_prose + " `notAManifestField` ") - names == {"notAManifestField"}:
    ok("rejected: coordination-identity.md backticking a camelCase token the schema does not define")
else:
    fail("the cross-check cannot fail on coordination-identity.md, so its field names are unchecked")

# The new file must also be carrying real field references, or the row above is
# a fixture test with nothing shipped behind it.
if len(referenced_in(_new_prose)) >= 4:
    ok(f"coordination-identity.md names {len(referenced_in(_new_prose))} manifest fields, all of which exist")
else:
    fail(f"coordination-identity.md names only {len(referenced_in(_new_prose))} manifest field(s), so the cross-check covers nothing there")

# The same three rows for this slice's new file, and they are not redundant with
# the block above: a references directory that stopped being globbed, or a file
# that was never added to it, leaves every row up there green. Each new file
# earns its own proof that the cross-check can fail ON IT.
PROVIDERS_MD = SKILL / "references/isolation-providers.md"
if not PROVIDERS_MD.exists():
    fail("references/isolation-providers.md is absent, so its field names are unchecked")
else:
    _prov_prose = PROVIDERS_MD.read_text()
    _prov_missing = sorted(referenced_in(_prov_prose) - names)
    if _prov_missing:
        fail(f"isolation-providers.md names fields absent from the schema: {_prov_missing}")
    elif referenced_in(_prov_prose + " `notAManifestField` ") - names == {"notAManifestField"}:
        ok("rejected: isolation-providers.md backticking a camelCase token the schema does not define")
    else:
        fail("the cross-check cannot fail on isolation-providers.md, so its field names are unchecked")

    if len(referenced_in(_prov_prose)) >= 2:
        ok(f"isolation-providers.md names {len(referenced_in(_prov_prose))} manifest field(s), all of which exist")
    else:
        fail(f"isolation-providers.md names only {len(referenced_in(_prov_prose))} manifest field(s), so the cross-check covers nothing there")

# The provider record itself: the schema must admit a copy reference beside the
# in-instance one, both in one entry, and an entry carrying neither. Three
# acceptances and three rejections, because a property that is merely OPTIONAL is
# satisfied by a schema that never validates it at all.
_iso_base = {"substrate": "x", "locality": {"value": "local", "reason": "r"},
             "isolation": {"mechanism": "none", "confidence": "declared"}}


def _store_case(iso):
    m = json.loads(json.dumps(example))
    m["backingStores"] = {"probe": {**_iso_base, "isolation": iso}}
    m["services"] = {}
    return m


def _validates(instance):
    return not list(validator.iter_errors(instance))


_good_provider = {"runtime": "docker", "sourceVolume": "v", "image": "i",
                  "baseInstance": "b", "confidence": "declared"}
for _label, _iso, _want in [
    ("a store carrying an in-instance record and a provider reference in one entry",
     {"mechanism": "database", "command": "c {{isolationIdent}}", "teardownCommand": "d {{isolationIdent}}",
      "confidence": "declared", "provider": _good_provider}, True),
    ("a store carrying a provider reference and no in-instance mechanism",
     {"mechanism": "none", "confidence": "declared", "provider": _good_provider}, True),
    ("a store carrying neither, which is the pair that refuses",
     {"mechanism": "none", "confidence": "declared"}, True),
    ("a provider reference with no sourceVolume, which is a copy with nothing to copy",
     {"mechanism": "none", "confidence": "declared",
      "provider": {"runtime": "docker", "image": "i", "baseInstance": "b", "confidence": "declared"}}, False),
    ("a provider reference naming a runtime this contract does not define",
     {"mechanism": "none", "confidence": "declared",
      "provider": {**_good_provider, "runtime": "managed"}}, False),
    ("a provider reference carrying an engine-shaped extra field",
     {"mechanism": "none", "confidence": "declared",
      "provider": {**_good_provider, "engine": "postgres"}}, False),
]:
    _valid = _validates(_store_case(_iso))
    if _valid is _want:
        ok(("accepted: " if _want else "rejected: ") + _label)
    else:
        fail(("REJECTED but must be accepted: " if _want else "ACCEPTED but must be rejected: ") + _label)

# The verification record: a candidate query, what makes it one, and what expires
# it. Three acceptances and five rejections, because the failure this record
# exists to stop is a store that LOOKS verified - a healthcheck copied in as a
# query with nothing establishing that it can tell a seeded instance from an
# empty one.
_probe_ok = {
    "command": ["CMD", "cat", "/data/marker"],
    "rung": 1,
    "sourceFingerprint": "cafebabe",
    "discriminates": {
        "value": True,
        "evidence": "answered 2 on the base store and 0 on an empty instance of the same image",
        "at": "2026-08-07T09:00:00Z",
    },
}


def _verification_case(v):
    m = json.loads(json.dumps(example))
    entry = {**_iso_base}
    if v is not None:
        entry["verification"] = v
    m["backingStores"] = {"probe": entry}
    m["services"] = {}
    return m


for _label, _v, _want in [
    ("a store recording a candidate, its rung, its fingerprint and a measured discrimination",
     _probe_ok, True),
    ("a store recording that its candidate does NOT discriminate, which is checked-and-not-a-query",
     {**_probe_ok, "discriminates": {**_probe_ok["discriminates"], "value": False,
                                     "evidence": "answered PONG on an empty instance too"}}, True),
    ("a store recording no candidate at all, which refuses at verification rather than at discovery",
     None, True),
    ("a candidate recorded as a shell line rather than an argument vector",
     {**_probe_ok, "command": "cat /data/marker"}, False),
    ("a candidate with no discrimination recorded, which is a healthcheck copied in as a query",
     {k: v for k, v in _probe_ok.items() if k != "discriminates"}, False),
    ("a discrimination claimed with an empty evidence string, which is a claim nobody ran",
     {**_probe_ok, "discriminates": {**_probe_ok["discriminates"], "evidence": ""}}, False),
    ("a candidate with no sourceFingerprint, so nothing could ever expire the probe result",
     {k: v for k, v in _probe_ok.items() if k != "sourceFingerprint"}, False),
    ("a candidate claiming rung 3, which is the absence of a candidate rather than a source",
     {**_probe_ok, "rung": 3}, False),
]:
    _valid = _validates(_verification_case(_v))
    if _valid is _want:
        ok(("accepted: " if _want else "rejected: ") + _label)
    else:
        fail(("REJECTED but must be accepted: " if _want else "ACCEPTED but must be rejected: ") + _label)

# The generated lifecycle family (DS37 as amended by DS42). This is the only
# record in the schema describing files the skill WROTE INTO SOMEBODY ELSE'S
# repository, so the two rules that matter are the ones a document cannot
# enforce: three files rather than two, and `declared` unreachable until a run
# has observed all three. Both are made structural here, because a rule that
# lives only in prose is a rule the next writer of a manifest does not meet.
_gen_files = {
    "create": "bin/db-create-postgres",
    "drop": "bin/db-drop-postgres",
    "read": "bin/db-read-postgres",
}
_gen_obs = {
    "create": {"at": "2026-08-07T09:00:00Z", "exit": 0},
    "drop": {"at": "2026-08-07T09:00:05Z", "exit": 0},
    "read": {"at": "2026-08-07T09:00:02Z", "exit": 0},
}


def _generated_case(gen, **over):
    """An isolation record carrying a generated family, plus its approval."""
    iso = {
        "mechanism": "database",
        "command": "bin/db-create-postgres {{isolationIdent}}",
        "teardownCommand": "bin/db-drop-postgres {{isolationIdent}}",
        "discoveredFrom": "bin/db-create-postgres",
        "approval": {"at": "2026-08-07T08:59:00Z", "sourceFingerprint": "cafebabe"},
        "confidence": "inferred",
    }
    iso.update(over)
    if gen is not None:
        iso["generated"] = gen
    return _store_case(iso)


for _label, _gen, _over, _want in [
    ("a generated family of three files that no run has exercised yet, recorded inferred",
     {"at": "2026-08-07T08:59:00Z", "directory": "bin/", "files": _gen_files, "observed": {}}, {}, True),
    ("a generated family raised to declared after a run observed all three succeed",
     {"at": "2026-08-07T08:59:00Z", "directory": "bin/", "files": _gen_files, "observed": _gen_obs},
     {"confidence": "declared"}, True),
    ("a generated family recorded declared with nothing observed, which is declared-on-write",
     {"at": "2026-08-07T08:59:00Z", "directory": "bin/", "files": _gen_files, "observed": {}},
     {"confidence": "declared"}, False),
    ("a generated family declared on a create and a drop with no read - DS37 as originally written, which leaves rung 2 with no source",
     {"at": "2026-08-07T08:59:00Z", "directory": "bin/", "files": _gen_files,
      "observed": {k: v for k, v in _gen_obs.items() if k != "read"}},
     {"confidence": "declared"}, False),
    ("a generated family declared on three observations one of which is a FAILURE, so an observation stands in for a success",
     {"at": "2026-08-07T08:59:00Z", "directory": "bin/", "files": _gen_files,
      "observed": {**_gen_obs, "create": {"at": "2026-08-07T09:00:00Z", "exit": 1}}},
     {"confidence": "declared"}, False),
    ("a family naming a create and a drop and no read at all, which is a chain that does not close",
     {"at": "2026-08-07T08:59:00Z", "directory": "bin/",
      "files": {k: v for k, v in _gen_files.items() if k != "read"}, "observed": {}}, {}, False),
    ("an observation carrying a timestamp and no exit status, which is an event that says nothing happened or otherwise",
     {"at": "2026-08-07T08:59:00Z", "directory": "bin/", "files": _gen_files,
      "observed": {"create": {"at": "2026-08-07T09:00:00Z"}}}, {}, False),
    ("an observation of a half nobody generates, which is a record about a file that does not exist",
     {"at": "2026-08-07T08:59:00Z", "directory": "bin/", "files": _gen_files,
      "observed": {"seed": {"at": "2026-08-07T09:00:00Z", "exit": 0}}}, {}, False),
    ("a generated family recorded with no directory, so nothing says where the skill wrote",
     {"at": "2026-08-07T08:59:00Z", "files": _gen_files, "observed": {}}, {}, False),
]:
    _valid = _validates(_generated_case(_gen, **_over))
    if _valid is _want:
        ok(("accepted: " if _want else "rejected: ") + _label)
    else:
        fail(("REJECTED but must be accepted: " if _want else "ACCEPTED but must be rejected: ") + _label)

# Consent is not implied by the record existing, and the two rows are separate
# because they fail for different reasons: no approval at all, and an approval
# with no file for its fingerprint to be taken against.
_no_approval = _generated_case(
    {"at": "2026-08-07T08:59:00Z", "directory": "bin/", "files": _gen_files, "observed": {}}
)
del _no_approval["backingStores"]["probe"]["isolation"]["approval"]
if _validates(_no_approval):
    fail("ACCEPTED but must be rejected: three files written into a repository with no approval recorded beside them")
else:
    ok("rejected: three files written into a repository with no approval recorded beside them")

_no_source = _generated_case(
    {"at": "2026-08-07T08:59:00Z", "directory": "bin/", "files": _gen_files, "observed": {}}
)
del _no_source["backingStores"]["probe"]["isolation"]["discoveredFrom"]
if _validates(_no_source):
    fail("ACCEPTED but must be rejected: an approval with no discoveredFrom, so no later edit could ever drop it")
else:
    ok("rejected: an approval with no discoveredFrom, so no later edit could ever drop it")

# ...and the whole block is only worth its rows while the base case validates.
# Every fixture above is a MUTATION of that case, so a base that was already
# invalid would have every negative passing for a reason none of them names -
# the same stand-down the version fixtures take when the shipped files do not read.
if _validates(_generated_case(
    {"at": "2026-08-07T08:59:00Z", "directory": "bin/", "files": _gen_files, "observed": {}}
)):
    ok("the generated-family base case validates, so each rejection above is attributable to the one thing it changed")
else:
    fail("the generated-family base case does not validate, so every rejection above fired for a reason it does not name")

print()
sys.exit(1 if fails else 0)
