# gemara-sample-evidence

## What lives here

The `gemara-sample-evidence` repository is a collection of tooling and versioned sample data. A deterministic sample evidence generator that produces known-good and known-bad [Gemara](https://gemara.openssf.org/) sample data. Sanitation ensures prevention of real data and credentials being leaked into test fixtures.

```
samples/
  good/                       # well-formed Gemara documents
    guidance-catalog.yaml
    mapping-document.yaml
  bad/                        # intentionally defective documents
    empty.yaml                  # 0-byte file
    malformed.yaml              # unparseable YAML
    missing-type.yaml           # no metadata.type
    missing-version.yaml        # no metadata.gemara-version
    wrong-type.yaml             # unrecognized metadata.type
scripts/
  generate-samples.sh          # assembles fixtures + dynamic files into .test-output/samples/
test/
  sample-generator.test.sh     # unit tests (no AWS needed)
```

All sample data targets **gemara-version 1.3.0**.

## Usage

### Static fixtures only

Clone and point your project at `samples/`:

```sh
git clone https://github.com/complytime-labs/gemara-sample-evidence.git
ls gemara-sample-evidence/samples/good/
```

### Full generation (static + dynamic)

The generator copies static fixtures and produces runtime-dependent files
(e.g. an oversized document exceeding `MAX_FILE_SIZE`).

```sh
make generate          # output in .test-output/samples/
make test              # run unit tests (requires python3 + PyYAML)
make clean             # remove .test-output/
```

### Consuming from another project

```sh
# As a git submodule
git submodule add https://github.com/complytime-labs/gemara-sample-evidence.git vendor/sample-evidence

# Point your test harness at the fixtures
export FIXTURES_DIR=vendor/sample-evidence/samples
bash vendor/sample-evidence/scripts/generate-samples.sh
```

### Environment variables

| Variable | Default | Description |
|---|---|---|
| `FIXTURES_DIR` | `samples/` | Path to static fixture directory |
| `SAMPLE_DIR` | `.test-output/samples` | Output directory for assembled samples |
| `MAX_FILE_SIZE` | `102400` | Byte threshold for oversized bad sample |
| `GENERATE_SAMPLES_LIB_ONLY` | unset | Set to `1` to source functions without running |

## Sanitization

The generator includes a sanitization check that rejects output containing:
- `arn:aws:` — real AWS ARN prefixes
- `AKIA` — AWS access key ID prefixes
- Non-synthetic 12-digit account IDs (only `000000000000` and `123456789012` are allowed)

## Process for contributions

<!-- Insert contribution procedure here>