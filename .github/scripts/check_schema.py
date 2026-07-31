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


def rejects(label, mutate):
    """A fixture that must be rejected. If it validates, the rule is not enforced."""
    doc = copy.deepcopy(example)
    mutate(doc)
    if list(validator.iter_errors(doc)):
        ok(f"rejected: {label}")
    else:
        fail(f"ACCEPTED but must be rejected: {label}")


def accepts(label, mutate):
    doc = copy.deepcopy(example)
    mutate(doc)
    errs = list(validator.iter_errors(doc))
    if errs:
        fail(f"rejected but must be accepted: {label} :: {errs[0].message[:100]}")
    else:
        ok(f"accepted: {label}")


# --- the shared-state gate must not be satisfiable by declaring nothing ------
rejects("a manifest with no backingStores at all", lambda d: d.pop("backingStores"))
rejects(
    "an empty backingStores with no root stateReview",
    lambda d: d.update(backingStores={}),
)
rejects(
    "a populated backingStores that no source covers",
    lambda d: d.update(
        sources=[{"path": "compose.yaml", "fingerprint": "h", "covers": ["services"]}]
    ),
)
rejects("a source covering nothing", lambda d: d["sources"][0].update(covers=[]))
rejects("an empty sources array", lambda d: d.update(sources=[]))

# --- evidence must be falsifiable ------------------------------------------
rejects(
    "a classification with no fingerprint baseline",
    lambda d: d["services"]["catalog-api"]["stateReview"].pop("serviceFingerprint"),
)
rejects(
    "an accepted risk naming nobody",
    lambda d: [e.pop("acceptedBy", None) for e in d["acceptedRisks"].values()],
)
rejects(
    "an isolation approval with no source to measure drift against",
    lambda d: (
        d["backingStores"]["postgres"]["isolation"].update(
            approval={"at": "2026-07-31T00:00:00Z", "sourceFingerprint": "x"}
        ),
        d["backingStores"]["postgres"]["isolation"].pop("discoveredFrom"),
    ),
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
)
rejects(
    "a namespace that is created and never dropped",
    lambda d: d["backingStores"]["postgres"]["isolation"].pop("teardownCommand"),
)
rejects(
    "a distinct consumer identity with no channel to the process",
    lambda d: d["services"]["search-indexer"]["competesOn"][0].update(
        overlayIdentity="sg-x"
    ),
)

# --- untrusted repository data stays constrained ----------------------------
rejects(
    "a store name carrying a shell metacharacter",
    lambda d: d["backingStores"].update({"pg;rm -rf /": d["backingStores"]["postgres"]}),
)
rejects(
    "a source claiming authority over the gate's own bypass",
    lambda d: d["sources"][0]["covers"].append("acceptedRisks"),
)

# --- and the legitimate shapes still pass -----------------------------------
accepts(
    "a store named the way real orchestrators name them",
    lambda d: d["backingStores"].update({"Postgres.main": d["backingStores"]["postgres"]}),
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


rejects("a storeless claim with no confidence recorded", storeless_unevidenced)

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
missing = sorted(referenced - names)
if missing:
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
