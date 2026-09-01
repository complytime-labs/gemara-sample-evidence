#!/usr/bin/env bash
# Unit-tests the sample evidence file generator without needing AWS or moto.
# Validates good files parse as YAML with correct structure, bad files have
# expected defects, and the sanitization check catches real-looking credentials.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"

# Point at the static fixtures checked into git.
export FIXTURES_DIR="$root/samples"

# Source the generator's functions without executing main.
GENERATE_SAMPLES_LIB_ONLY=1 source "$root/scripts/generate-samples.sh"

# Use an isolated output dir under .test-output/.
TEST_DIR="$root/.test-output/sample-gen-test"
rm -rf "$TEST_DIR"
export SAMPLE_DIR="$TEST_DIR"
export GOOD_DIR="${TEST_DIR}/good"
export BAD_DIR="${TEST_DIR}/bad"
export MAX_FILE_SIZE=102400

pass=0
fail=0

assert_eq() {
	local label="$1" expected="$2" got="$3"
	if [ "$expected" = "$got" ]; then
		pass=$((pass + 1))
	else
		echo "FAIL: $label: expected '$expected', got '$got'" >&2
		fail=$((fail + 1))
	fi
}

assert_file_exists() {
	local label="$1" path="$2"
	if [ -f "$path" ]; then
		pass=$((pass + 1))
	else
		echo "FAIL: $label: file does not exist: $path" >&2
		fail=$((fail + 1))
	fi
}

# ---------------------------------------------------------------------------
# Generate all files (copies fixtures + generates oversized)
# ---------------------------------------------------------------------------
generate_all

# ---------------------------------------------------------------------------
# Good files: exist and parse as valid YAML with correct metadata
# ---------------------------------------------------------------------------

# GuidanceCatalog: exists, parses, has required fields
assert_file_exists "good/guidance-catalog exists" "$GOOD_DIR/guidance-catalog.yaml"

python3 - "$GOOD_DIR/guidance-catalog.yaml" <<'PY'
import sys, yaml
with open(sys.argv[1]) as fh:
    doc = yaml.safe_load(fh)
assert isinstance(doc, dict), "not a YAML mapping"
m = doc.get("metadata", {})
assert m.get("type") == "GuidanceCatalog", f"type: {m.get('type')}"
assert m.get("gemara-version") == "1.3.0", f"version: {m.get('gemara-version')}"
assert m.get("id"), "missing metadata.id"
assert isinstance(doc.get("groups"), list) and len(doc["groups"]) > 0, "groups empty"
assert isinstance(doc.get("guidelines"), list) and len(doc["guidelines"]) > 0, "guidelines empty"
PY
assert_eq "good/guidance-catalog parses with correct fields" "0" "$?"

# MappingDocument: exists, parses, has required fields
assert_file_exists "good/mapping-document exists" "$GOOD_DIR/mapping-document.yaml"

python3 - "$GOOD_DIR/mapping-document.yaml" <<'PY'
import sys, yaml
with open(sys.argv[1]) as fh:
    doc = yaml.safe_load(fh)
assert isinstance(doc, dict), "not a YAML mapping"
m = doc.get("metadata", {})
assert m.get("type") == "MappingDocument", f"type: {m.get('type')}"
assert m.get("gemara-version") == "1.3.0", f"version: {m.get('gemara-version')}"
assert m.get("id"), "missing metadata.id"
assert doc.get("source-reference"), "missing source-reference"
assert doc.get("target-reference"), "missing target-reference"
assert isinstance(doc.get("mappings"), list) and len(doc["mappings"]) > 0, "mappings empty"
PY
assert_eq "good/mapping-document parses with correct fields" "0" "$?"

# ---------------------------------------------------------------------------
# Bad files: exist and have expected defects
# ---------------------------------------------------------------------------

# missing-type: valid YAML, no metadata.type
assert_file_exists "bad/missing-type exists" "$BAD_DIR/missing-type.yaml"

python3 - "$BAD_DIR/missing-type.yaml" <<'PY'
import sys, yaml
with open(sys.argv[1]) as fh:
    doc = yaml.safe_load(fh)
m = doc.get("metadata", {})
assert "type" not in m, f"expected no metadata.type, found: {m.get('type')}"
PY
assert_eq "bad/missing-type lacks metadata.type" "0" "$?"

# wrong-type: valid YAML, metadata.type is not a recognized value
assert_file_exists "bad/wrong-type exists" "$BAD_DIR/wrong-type.yaml"

python3 - "$BAD_DIR/wrong-type.yaml" <<'PY'
import sys, yaml
with open(sys.argv[1]) as fh:
    doc = yaml.safe_load(fh)
m = doc.get("metadata", {})
t = m.get("type", "")
assert t not in ("GuidanceCatalog", "MappingDocument"), f"type should be invalid, got: {t}"
assert t, "type should exist but be wrong"
PY
assert_eq "bad/wrong-type has invalid metadata.type" "0" "$?"

# malformed: not parseable as YAML
assert_file_exists "bad/malformed exists" "$BAD_DIR/malformed.yaml"

if python3 -c "
import sys, yaml
with open(sys.argv[1]) as fh:
    yaml.safe_load(fh)
" "$BAD_DIR/malformed.yaml" 2>/dev/null; then
	echo "FAIL: bad/malformed should not parse as valid YAML" >&2
	fail=$((fail + 1))
else
	pass=$((pass + 1))
fi

# empty: exists but empty
assert_file_exists "bad/empty exists" "$BAD_DIR/empty.yaml"
size=$(wc -c <"$BAD_DIR/empty.yaml" | tr -d ' ')
assert_eq "bad/empty is 0 bytes" "0" "$size"

# missing-version: valid YAML, no gemara-version
assert_file_exists "bad/missing-version exists" "$BAD_DIR/missing-version.yaml"

python3 - "$BAD_DIR/missing-version.yaml" <<'PY'
import sys, yaml
with open(sys.argv[1]) as fh:
    doc = yaml.safe_load(fh)
m = doc.get("metadata", {})
assert "gemara-version" not in m, f"expected no gemara-version, found: {m.get('gemara-version')}"
PY
assert_eq "bad/missing-version lacks gemara-version" "0" "$?"

# oversized: exceeds MAX_FILE_SIZE
assert_file_exists "bad/oversized exists" "$BAD_DIR/oversized.yaml"
size=$(wc -c <"$BAD_DIR/oversized.yaml" | tr -d ' ')
if [ "$size" -gt "$MAX_FILE_SIZE" ]; then
	pass=$((pass + 1))
else
	echo "FAIL: bad/oversized is $size bytes, expected > $MAX_FILE_SIZE" >&2
	fail=$((fail + 1))
fi

# ---------------------------------------------------------------------------
# Static fixtures: output matches checked-in fixtures byte-for-byte
# ---------------------------------------------------------------------------

fixtures_match=true
for subdir in good bad; do
	for f in "$FIXTURES_DIR/$subdir"/*.yaml; do
		fname="$(basename "$f")"
		out_file="$TEST_DIR/$subdir/$fname"
		if [ -f "$out_file" ] && ! diff -q "$f" "$out_file" >/dev/null 2>&1; then
			echo "FAIL: $subdir/$fname differs from fixture" >&2
			fixtures_match=false
		fi
	done
done
if $fixtures_match; then
	pass=$((pass + 1))
else
	fail=$((fail + 1))
fi

# ---------------------------------------------------------------------------
# Sanitization: clean output passes, injected ARN fails
# ---------------------------------------------------------------------------

# Clean check should pass
if sanitize_check "$TEST_DIR" >/dev/null 2>&1; then
	pass=$((pass + 1))
else
	echo "FAIL: sanitize_check should pass on clean generated output" >&2
	fail=$((fail + 1))
fi

# Inject a real ARN and confirm sanitize_check catches it
inject_file="$GOOD_DIR/injected-arn.yaml"
cat >"$inject_file" <<'YAML'
metadata:
  id: injected
  type: GuidanceCatalog
  gemara-version: "1.3.0"
  resource: "arn:aws:s3:::real-production-bucket"
YAML

if sanitize_check "$TEST_DIR" >/dev/null 2>&1; then
	echo "FAIL: sanitize_check should fail when ARN is injected" >&2
	fail=$((fail + 1))
else
	pass=$((pass + 1))
fi

# Clean up injected file
rm -f "$inject_file"

# Inject an AKIA key and confirm sanitize_check catches it
inject_file="$GOOD_DIR/injected-key.yaml"
cat >"$inject_file" <<'YAML'
metadata:
  id: injected-key
  access_key: "AKIAIOSFODNN7EXAMPLE"
YAML

if sanitize_check "$TEST_DIR" >/dev/null 2>&1; then
	echo "FAIL: sanitize_check should fail when AKIA key is injected" >&2
	fail=$((fail + 1))
else
	pass=$((pass + 1))
fi

rm -f "$inject_file"

# ---------------------------------------------------------------------------
# Determinism: two runs produce identical output
# ---------------------------------------------------------------------------
run1_dir="$root/.test-output/sample-gen-determ-1"
run2_dir="$root/.test-output/sample-gen-determ-2"
rm -rf "$run1_dir" "$run2_dir"

# Must set all derived variables — GOOD_DIR/BAD_DIR are set at source time,
# not dynamically derived inside generate_all.
SAMPLE_DIR="$run1_dir" GOOD_DIR="$run1_dir/good" BAD_DIR="$run1_dir/bad" generate_all >/dev/null 2>&1
SAMPLE_DIR="$run2_dir" GOOD_DIR="$run2_dir/good" BAD_DIR="$run2_dir/bad" generate_all >/dev/null 2>&1

if diff -r "$run1_dir" "$run2_dir" >/dev/null 2>&1; then
	pass=$((pass + 1))
else
	echo "FAIL: two generator runs produced different output" >&2
	fail=$((fail + 1))
fi

rm -rf "$run1_dir" "$run2_dir"

# ---------------------------------------------------------------------------
# Idempotency: re-run over existing output succeeds
# ---------------------------------------------------------------------------
SAMPLE_DIR="$TEST_DIR" generate_all >/dev/null 2>&1
assert_eq "idempotent re-run exits 0" "0" "$?"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "sample-generator unit test: $pass passed, $fail failed"
if [ "$fail" -gt 0 ]; then
	exit 1
fi
