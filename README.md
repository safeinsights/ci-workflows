# ci-workflows

Shared GitHub Actions workflows for SafeInsights repos. They replace the Jenkins shared library
(SHRMP-343).

| Workflow | What it does |
|---|---|
| [`harbor-image.yaml`](.github/workflows/harbor-image.yaml) | Builds and Trivy-scans a Docker image on every run; on `main`, pushes it to Harbor and signs it |
| [`trivy-fs.yaml`](.github/workflows/trivy-fs.yaml) | Scans the repo for committed secrets (fails) and misconfigurations (reported) |
| [`semgrep.yaml`](.github/workflows/semgrep.yaml) | Static analysis (SAST) with Semgrep CE: SafeInsights rules plus registry packs, annotates findings, keeps one PR comment current, fails on ERROR |
| [`sonarqube.yaml`](.github/workflows/sonarqube.yaml) | Runs a SonarQube scan, optionally with a coverage artifact from another job |

## Access

This repo is **private**. Before other repos can call these workflows, an admin must set
**Settings → Actions → General → Access** to "Accessible from repositories in the
'safeinsights' organization". Public repos (e.g. management-app) can't call workflows in a
private repo at all; make this repo public if they need them. Nothing secret is stored here,
because callers pass their own secrets in.

## Versioning

Pin callers to a full commit SHA, with the release tag as a comment, and let Dependabot
propose updates:

```yaml
uses: safeinsights/ci-workflows/.github/workflows/harbor-image.yaml@<commit sha> # v4.0.0
```

Release by tagging `main` with a semver tag (`v1.0.0`, ...). A change to the inputs that would
break existing callers needs a new major version.

### Migrating from v1 to v2

v2.0.0 adds security gates to `harbor-image.yaml` that can fail builds which passed on v1:

- **Image scan:** every build is scanned with Trivy, and fixable `CRITICAL` vulnerabilities fail it
  before anything is pushed. Fix them (e.g. `apt-get upgrade` in the Dockerfile), accept specific ones
  with a `trivyignores` file, or change the threshold with `fail-on-severity`.
- **Signing:** pushes are signed with cosign. Add the `COSIGN_PRIVATE_KEY` and `COSIGN_PASSWORD`
  repo secrets and pass them in `secrets:`. A push without the key now fails up front.
- **Single platform:** `platforms` must name one platform (the scanned image is the pushed image).
- **New workflows:** `trivy-fs.yaml` (repo scan) and `semgrep.yaml` (static analysis; called
  `opengrep.yaml` in v2) are opt-in.

### Migrating from v2 to v3

v3.0.0 replaces Opengrep with Semgrep Community Edition and renames the workflow:

- `uses: .../opengrep.yaml@…` becomes `uses: .../semgrep.yaml@…`. The inputs (`registry-configs`,
  `exclude`, `fail-on`) and the `pull-requests: write` requirement are unchanged.
- The default registry packs grow from `p/python p/dockerfile` to
  `p/ci p/secrets p/python p/dockerfile p/github-actions p/javascript p/typescript`, so a repo that
  passed on v2 can gain findings. Pass `registry-configs` explicitly to keep the old set.
- A `.semgrepignore` in the caller's repo is now honoured. It replaces Semgrep's built-in ignore
  list (`.git`, `node_modules`, …), so restate those entries in it.
- Existing `# nosemgrep: <rule-id>` suppressions work unchanged.

### Migrating from v3 to v4

v4.0.0 moves the Harbor and cosign secrets out of pull requests' reach:

- `harbor-image.yaml` has a new required input, `environment`, and runs as two jobs: `build` (PRs,
  no secrets) and `push` (`main` only, inside that environment). A caller that gated on the job
  name `build` now sees `build` on PRs and `push` on `main`.
- Create the environment with a `main`-only deployment branch policy and move the four secrets
  into it; see "Setting up a caller". Until the secrets are moved, the `push` job fails its secret
  check and nothing is pushed.

## `harbor-image.yaml`

Every run builds the image and scans it with Trivy. Fixable HIGH and CRITICAL vulnerabilities are
listed in the job summary. Fixable vulnerabilities at `fail-on-severity` fail the job before
anything is pushed. Two jobs share those steps:

- `build` runs on pull requests and on branches other than `main`. It holds no secret.
- `push` runs only when `push` is true (the default), the event is not a pull request, and the ref
  is `main`. It runs inside the caller's `environment`, builds and scans again, pushes, then signs
  the pushed digest with cosign and verifies the signature. The image that was scanned in this job
  is the image that is pushed and signed.

The split is what keeps the secrets off pull requests: a PR can edit the caller's workflow, but a
job it adds cannot enter an environment whose deployment branch policy allows `main` only, and
the secrets exist nowhere else.

| Input | Default | Notes |
|---|---|---|
| `image` | required | e.g. `harbor.safeinsights.org/openstax/r-base` |
| `tag` | required | Template: `{date}` (UTC `YYYY-MM-DD`), `{sha}`, `{sha8}`, e.g. `4.5.1-{date}-{sha8}` |
| `environment` | required | GitHub environment in the caller's repo that holds the four secrets below; see "Setting up a caller" |
| `context` | `.` | Build context in the caller's repo |
| `file` | `<context>/Dockerfile` | |
| `platforms` | `linux/amd64` | One platform only; the image is loaded locally so the scanned image is the pushed one. BuildKit provenance is not attached for the same reason |
| `push` | `true` | `false` never pushes |
| `fail-on-severity` | `CRITICAL` | e.g. `HIGH,CRITICAL` to be stricter |
| `trivyignores` | none | Path to a `.trivyignore.yaml` in the caller's repo, for accepted findings |
| `timeout-minutes` | `90` | |

Secrets (all needed only when pushing): `HARBOR_USERNAME`, `HARBOR_TOKEN`, `COSIGN_PRIVATE_KEY`,
`COSIGN_PASSWORD`. The caller passes them by name as usual; GitHub resolves them from the
environment named in `environment`. A missing `HARBOR_USERNAME`, `HARBOR_TOKEN` or
`COSIGN_PRIVATE_KEY` fails the `push` job before it builds, so an unsigned image never reaches
Harbor. Outputs: `image-ref`, `digest`.

### Setting up a caller

1. In the calling repo, create an environment (the examples use `harbor`) with **Deployment
   branches and tags → Selected branches and tags → `main`**. Create it before the first run on
   `main`: a job that names a missing environment creates it with no branch policy.
2. Add the four secrets to that environment, not as repository secrets, and remove any repository
   secrets of the same name. A secret that exists only in the environment is empty on a pull
   request, which is the point. (SafeInsights uses no org secrets.)
3. Pass `environment: harbor` in `with:`.

### Signing key

Images are signed with an org key pair, and the signatures are **not** sent to Sigstore's public
transparency log. That keeps these private repos' names and digests out of a public record. The
trade-off is that the key has to be managed:

1. Generate the pair once: `cosign generate-key-pair` (it asks for a password).
2. Store `cosign.key` as `COSIGN_PRIVATE_KEY` and the password as `COSIGN_PASSWORD` in each
   calling repo's environment (see "Setting up a caller"). Then delete the local `cosign.key`.
3. Publish `cosign.pub` where verifiers can read it.

Verify an image:

```bash
cosign verify --key cosign.pub --insecure-ignore-tlog=true harbor.safeinsights.org/openstax/r-base@sha256:<digest>
```

`--insecure-ignore-tlog` is expected here: there is no transparency log entry to check.

```yaml
jobs:
  build:
    strategy:
      fail-fast: false
      matrix:
        include:
          - { dir: python-3.12, image: openstax/python-base, tag: '3.12-{date}-{sha8}' }
          - { dir: r-4.5.1, image: openstax/r-base, tag: '4.5.1-{date}-{sha8}' }
    uses: safeinsights/ci-workflows/.github/workflows/harbor-image.yaml@<commit sha> # v4.0.0
    with:
      image: harbor.safeinsights.org/${{ matrix.image }}
      tag: ${{ matrix.tag }}
      context: ${{ matrix.dir }}
      environment: harbor
    secrets:
      HARBOR_USERNAME: ${{ secrets.HARBOR_USERNAME }}
      HARBOR_TOKEN: ${{ secrets.HARBOR_TOKEN }}
      COSIGN_PRIVATE_KEY: ${{ secrets.COSIGN_PRIVATE_KEY }}
      COSIGN_PASSWORD: ${{ secrets.COSIGN_PASSWORD }}
```

## `trivy-fs.yaml`

Scans the caller's repo. Any committed secret fails the job. HIGH and CRITICAL misconfigurations,
such as Dockerfiles that run as root, are listed in the job summary without failing.

| Input | Default | Notes |
|---|---|---|
| `trivyignores` | none | Path to a `.trivyignore.yaml` in the caller's repo, for accepted findings |

```yaml
jobs:
  trivy:
    uses: safeinsights/ci-workflows/.github/workflows/trivy-fs.yaml@<commit sha> # v4.0.0
```

## `semgrep.yaml`

Scans the caller's repo with Semgrep Community Edition (public rulesets, no account, no token).
Semgrep is installed by [`.github/actions/setup-semgrep`](.github/actions/setup-semgrep) from a
hash-locked `uv.lock`, the uv equivalent of a SHA-pinned action, with a pinned uv. Dependabot
proposes Semgrep bumps (`uv` ecosystem); the manual procedure and the uv pin are described in the
action's `pyproject.toml`. Two sets of rules run:

- **SafeInsights rules** bundled in [`.github/actions/semgrep/rules`](.github/actions/semgrep/rules):
  `python-security`, `r-security` and `secrets`. They are copied from iac's researcher-code scanner
  (`management-app/codebuild/scripts/semgrep-rules`, iac commit `c49c9bd`). When those rules change
  in iac, copy them here along with their fixtures in `tests/semgrep`.
- **Registry packs** (`registry-configs`), fetched from the Semgrep registry at scan time. They are
  not pinned, so results can change between runs. They are covered by the Semgrep Rules License,
  which allows this kind of internal use.

Language coverage, with the default packs:

| Language | Covered by |
|---|---|
| Python | bundled `python-security` + `p/python`, `p/ci`, `p/secrets` |
| R | bundled `r-security` only: the Semgrep registry has **no R pack** |
| Dockerfiles | `p/dockerfile` |
| GitHub Actions workflows | `p/github-actions` |
| JavaScript / TypeScript | `p/javascript`, `p/typescript`, `p/ci` |
| Shell, YAML, everything else | `p/ci` and `p/secrets` where they have rules; there are no `p/bash` or `p/yaml` packs |

Every non-INFO finding becomes an annotation on its line; GitHub shows the first 10 errors and 10
warnings per step. On a PR, the full report goes into a single comment that is edited on each push.
Findings at `fail-on` (default `ERROR`) fail the job. Registry rules also use Semgrep's
CRITICAL/HIGH/MEDIUM/LOW scale; those count as ERROR, ERROR, WARNING and INFO for `fail-on`, and
the report shows both, e.g. `ERROR (CRITICAL)`.

The calling job **must grant `pull-requests: write`**, or GitHub rejects the run. If the comment
can't be posted (e.g. Dependabot's read-only token), the scan still runs and the gate still applies.

| Input | Default | Notes |
|---|---|---|
| `registry-configs` | `p/ci p/secrets p/python p/dockerfile p/github-actions p/javascript p/typescript` | Space-separated; empty for bundled rules only |
| `exclude` | none | Space-separated paths or globs, e.g. `.old` |
| `fail-on` | `ERROR` | Comma-separated severities |

Without a `.semgrepignore` at the caller's repo root, Semgrep's built-in ignore list applies, at any
depth: VCS and package-manager directories (`.git`, `.svn`, `.hg`, `_darcs`, `CVS`, `node_modules/`,
`.npm/`, `.yarn/`, `.venv/`, `.env/`, `.tox/`, `_opam/`, `_build/`, `_cargo/`), build output
(`build/`, `dist/`, `vendor/`, `*.min.js`) and **test trees** (`test/`, `tests/`, `testsuite/`,
`*_test.go`). So Semgrep does not look at tests; `trivy-fs.yaml` still scans them for secrets. A
root `.semgrepignore` **replaces** that list entirely: an empty one scans everything, and one that
restates only `.git/`, `node_modules/` and `.venv/` scans the test trees too.

```yaml
jobs:
  semgrep:
    permissions:
      contents: read
      pull-requests: write
    uses: safeinsights/ci-workflows/.github/workflows/semgrep.yaml@<commit sha> # v4.0.0
```

To accept a specific finding, add a `# nosemgrep: <rule-id>` comment with a reason on the line of
the match or the line before it.

## `sonarqube.yaml`

Reads `sonar-project.properties` from the caller's repo root. It never runs the caller's code,
because `SONAR_TOKEN` would be exposed to it. Run tests in another job and pass coverage in as an
artifact. It skips Dependabot runs, because those get no secrets.

| Input | Default | Notes |
|---|---|---|
| `coverage-artifact` | empty (no coverage) | Name of an artifact uploaded by an earlier job |
| `coverage-path` | `.` | Where to download it, matching the paths in `sonar-project.properties` |

Secrets: `SONAR_TOKEN`, `SONAR_HOST_URL`.

```yaml
jobs:
  sonarqube:
    needs: test-Python
    uses: safeinsights/ci-workflows/.github/workflows/sonarqube.yaml@<commit sha> # v4.0.0
    with:
      coverage-artifact: python-coverage
      coverage-path: python-3.12
    secrets:
      SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
      SONAR_HOST_URL: ${{ secrets.SONAR_HOST_URL }}
```

## Testing changes

`self-test.yaml` runs on every PR. It runs actionlint, tests the bundled Semgrep rules against
their fixtures (`semgrep scan --test`), scans this repo with `semgrep.yaml` and `trivy-fs.yaml`, and
builds and scans `tests/fixtures/hello` through `harbor-image.yaml` without pushing. Pushing and
signing only happen on a caller's `main`, so the first such run is the real test of a change to
those steps. Locally: `actionlint` from the repo root.
