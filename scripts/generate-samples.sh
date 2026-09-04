#!/usr/bin/env bash
# Assemble the test sample directory from static fixtures and dynamically
# generated files.
#
# Static fixtures live in samples/{good,bad}/ and are checked into git so
# external projects can consume them directly. This script copies them into
# the build output directory and generates the files that truly require
# runtime construction (e.g. the oversized file whose size depends on
# MAX_FILE_SIZE).
#
# Output: .test-output/samples/{good,bad}/
# All content is synthetic — no real ARNs, account IDs, or credentials.
#
# Usage:
#   generate-samples.sh              # assemble + sanitization check
#   GENERATE_SAMPLES_LIB_ONLY=1 source generate-samples.sh  # source functions
#
# gemara-version reference: 1.3.0
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

FIXTURES_DIR="${FIXTURES_DIR:-${REPO_ROOT}/samples}"
SAMPLE_DIR="${SAMPLE_DIR:-.test-output/samples}"
GOOD_DIR="${SAMPLE_DIR}/good"
BAD_DIR="${SAMPLE_DIR}/bad"

# Maximum file size for evidence files (bytes). The oversized bad sample
# exceeds this threshold.
MAX_FILE_SIZE="${MAX_FILE_SIZE:-102400}"

# ---------------------------------------------------------------------------
# Copy static fixtures into the output directory
# ---------------------------------------------------------------------------

copy_fixtures() {
	cp "${FIXTURES_DIR}/good/guidance-catalog.yaml" "${GOOD_DIR}/guidance-catalog.yaml"
	cp "${FIXTURES_DIR}/good/mapping-document.yaml" "${GOOD_DIR}/mapping-document.yaml"

	cp "${FIXTURES_DIR}/bad/missing-type.yaml"      "${BAD_DIR}/missing-type.yaml"
	cp "${FIXTURES_DIR}/bad/wrong-type.yaml"         "${BAD_DIR}/wrong-type.yaml"
	cp "${FIXTURES_DIR}/bad/malformed.yaml"          "${BAD_DIR}/malformed.yaml"
	cp "${FIXTURES_DIR}/bad/empty.yaml"              "${BAD_DIR}/empty.yaml"
	cp "${FIXTURES_DIR}/bad/missing-version.yaml"    "${BAD_DIR}/missing-version.yaml"
}

# ---------------------------------------------------------------------------
# Dynamic generators — files whose content depends on runtime parameters
# ---------------------------------------------------------------------------

generate_bad_oversized() {
	# Generate a file exceeding MAX_FILE_SIZE by repeating a valid-looking block.
	local target_size out
	target_size=$((MAX_FILE_SIZE + 1024))
	out="${BAD_DIR}/oversized.yaml"

	cat >"$out" <<'YAML'
metadata:
  id: oversized-doc
  type: GuidanceCatalog
  gemara-version: "1.3.0"
  description: "Intentionally oversized document"
  author:
    id: "test-org"
    name: "Test Organization"
    type: "Software Assisted"
title: "Oversized Document"
groups:
  - id: PAD
    title: Padding
    description: Filler group for size testing.
guidelines:
YAML
	local seq=1
	while [ "$(wc -c <"$out")" -lt "$target_size" ]; do
		cat >>"$out" <<YAML
  - id: "PAD.$(printf '%05d' $seq)"
    title: "Padding guideline $seq"
    objective: "Filler content to exceed the maximum file size threshold."
    group: "PAD"
    statements:
      - id: "PAD.$(printf '%05d' $seq).01"
        title: "Filler statement $seq"
        text: "This statement exists solely to increase the file size beyond the allowed maximum for evidence artifacts."
YAML
		seq=$((seq + 1))
	done
}

# ---------------------------------------------------------------------------
# Sanitization check
# ---------------------------------------------------------------------------

sanitize_check() {
	# Verify no generated file contains real-looking AWS credentials or ARNs.
	# Patterns checked:
	#   - arn:aws:  (real ARN prefix)
	#   - AKIA     (access key ID prefix)
	#   - 12-digit numbers that aren't clearly synthetic (000000000000, 123456789012)
	local dir="${1:-${SAMPLE_DIR}}"
	local found=0

	# Real ARN prefix
	if grep -rn 'arn:aws:' "$dir" 2>/dev/null; then
		echo "error: found real AWS ARN pattern in generated samples" >&2
		found=1
	fi

	# AWS access key ID prefix
	if grep -rn 'AKIA' "$dir" 2>/dev/null; then
		echo "error: found AWS access key ID pattern in generated samples" >&2
		found=1
	fi

	# 12-digit account IDs that aren't synthetic placeholders.
	# Synthetic: 000000000000, 123456789012. Everything else is suspect.
	# Use grep -E (POSIX ERE) for portability — macOS grep lacks -P.
	if grep -rEn '(^|[^0-9])[0-9]{12}([^0-9]|$)' "$dir" 2>/dev/null \
		| grep -Ev '(000000000000|123456789012)'; then
		echo "error: found non-synthetic 12-digit account ID in generated samples" >&2
		found=1
	fi

	return "$found"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

generate_all() {
	mkdir -p "${GOOD_DIR}" "${BAD_DIR}"

	copy_fixtures
	generate_bad_oversized

	sanitize_check
}

# Allow sourcing for unit tests without executing main.
if [[ "${GENERATE_SAMPLES_LIB_ONLY:-}" == "1" ]]; then
	return 0 2>/dev/null || true
fi

generate_all
echo "sample generation OK — output in ${SAMPLE_DIR}"
