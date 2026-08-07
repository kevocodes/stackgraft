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
rejects(
    "a distinct consumer identity with no channel to the process",
    lambda d: d["services"]["search-indexer"]["competesOn"][0].update(
        overlayIdentity="sg-x"
    ),
    "/properties/services/additionalProperties/properties/competesOn"
    "/items/allOf/0/then/required",
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

print()
sys.exit(1 if fails else 0)
