# ci-workflows

Shared GitHub Actions workflows for SafeInsights repos. They replace the Jenkins shared library
(SHRMP-343).

| Workflow | What it does |
|---|---|
| [`harbor-image.yaml`](.github/workflows/harbor-image.yaml) | Builds and Trivy-scans a Docker image on every run; on `main`, pushes it to Harbor and signs it |
| [`trivy-fs.yaml`](.github/workflows/trivy-fs.yaml) | Scans the repo for committed secrets (fails) and misconfigurations (reported) |
| [`semgrep.yaml`](.github/workflows/semgrep.yaml) | Static analysis (SAST) with Semgrep CE: SafeInsights rules plus registry packs, annotates findings, keeps one PR comment current, fails on ERROR |
| [`sonarqube.yaml`](.github/workflows/sonarqube.yaml) | Runs a SonarQube scan, optionally with a coverage artifact from another job |
| [`ai-code-review.yaml`](.github/workflows/ai-code-review.yaml) | Reviews a pull request with OpenAI Codex (GPT-6.1 on Amazon Bedrock) and keeps one review comment current; skips drafts, bots and PRs from forks |

## Access

This repo is **public** so that the org's public repos (e.g. management-app) can call
`ai-code-review.yaml`: a public repo cannot call a reusable workflow that lives in a private one.
Nothing secret is stored here, because callers pass their own secrets in.

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
- **Two scans are added** (both were in mars-university's own pipeline): the image scan also
  looks for secrets in layers, and `trivy-fs.yaml` also scans dependency manifests and lockfiles,
  failing on fixable CRITICAL vulnerabilities (`fail-on-severity`). A repo that passed on v3 can
  gain findings; `trivyignores` accepts specific ones.

## `harbor-image.yaml`

Every run builds the image and scans it with Trivy for vulnerabilities and for secrets baked into
a layer. Fixable HIGH and CRITICAL findings are listed in the job summary. Fixable findings at
`fail-on-severity` fail the job before anything is pushed. Two jobs share those steps:

- `build` runs on pull requests and on branches other than `main`. It holds no secret.
- `push` runs only when `push` is true (the default), the event is not a pull request, and the ref
  is `main`. It runs inside the caller's `environment`, builds and scans again, pushes, then signs
  the pushed digest with cosign and verifies the signature. The image that was scanned in this job
  is the image that is pushed and signed.

The split is what keeps the secrets off pull requests: a PR can edit the caller's workflow, but a
job it adds cannot enter an environment whose deployment branch policy allows `main` only. That
holds only while the secrets exist nowhere else. A repository secret of the same name still reaches
PR runs, and the `push` job cannot tell which copy it got, so step 2 below deletes them.

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
   branches and tags → Selected branches and tags → `main`**, or fix an existing one: check that
   its policy is exactly that before moving any secret into it. "No restriction" admits pull
   requests, and "Protected branches only" admits every protected branch. Create it before the
   first run on `main`: a job that names a missing environment creates it with no branch policy.
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

Scans the caller's repo. Any committed secret fails the job, and so does a fixable vulnerability
at `fail-on-severity` in a dependency manifest or lockfile (dev dependencies included where Trivy
distinguishes them: npm, yarn, gradle). HIGH and CRITICAL misconfigurations, such as Dockerfiles that run as root, and the
other fixable HIGH/CRITICAL dependency vulnerabilities are listed in the job summary without
failing. Trivy does not index CRAN, so R packages are not covered.

| Input | Default | Notes |
|---|---|---|
| `trivyignores` | none | Path to a `.trivyignore.yaml` in the caller's repo, for accepted findings |
| `fail-on-severity` | `CRITICAL` | e.g. `HIGH,CRITICAL` to be stricter |

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

## `ai-code-review.yaml`

Runs [OpenAI Codex](https://github.com/openai/codex) on a pull request and posts its review as
one comment from `github-actions[bot]`, edited in place on later runs. Inference runs on Amazon Bedrock
in the si-devops AWS account: the job exchanges its GitHub OIDC token for
`github-code-review-bedrock-role` (defined in
[`iac/github-code-review`](https://github.com/safeinsights/iac/tree/main/github-code-review)) and
Codex's `amazon-bedrock` provider picks those credentials up from the AWS SDK chain, so there is no
API key, GitHub App or secret anywhere. The caller's own `GITHUB_TOKEN` fetches the diff and posts
the comment; Codex never sees it.

| Input | Default | Notes |
|---|---|---|
| `model` | `openai.gpt-6.1-sol` | Bedrock Mantle model ID. Sol is the Opus-class model (about $2.20 in / $11 out per million tokens); the role also allows `openai.gpt-6.1-terra`, the Sonnet-class model at about half that |

Not reviewed, by design:

- **PRs from forks.** GitHub issues no OIDC token to a run started from a fork, so the job skips them
  (`if:`) rather than failing at the credentials step. On public repos, external contributors' PRs get
  no bot review; push the branch into the repo to get one.
- **Draft PRs**, until marked ready for review.
- **PRs opened by bots** such as Dependabot: version bumps that a human gates anyway.

Only PRs from branches in the same repository run, so the author already has write access. The
`codex exec` CLI is run directly rather than through `openai/codex-action`: that action cannot run
without an OpenAI API key, because the proxy it starts to keep the key away from Codex is mandatory,
and here Codex authenticates with the job's AWS credentials itself. Codex runs in its read-only
sandbox against a checkout that holds no token, with web search off, with only the core environment
passed to the commands it runs (the AWS session is not in their environment) and under `no_new_privs`
so `sudo` is inert. The job has `contents: read`, `pull-requests: write`, `id-token: write` only. The
worst a hostile PR can realistically do is steer the review comment on itself; the credentials Codex
itself holds last an hour and are good for nothing but calling the two allowed models, which the
budget bounds. (The `GITHUB_ENV` file the credentials step wrote is not on disk either: the runner
deletes each step's command files when the next step starts.) And anyone able to open such a PR
already has `id-token: write` in a `safeinsights` repo and could assume the role from a workflow of
their own, so a review steered into exposing the session would gain them nothing they lack.

The Codex CLI version is pinned in the workflow (`CODEX_VERSION`) and bumped by hand, since Dependabot
does not see npm installs in `run` steps.

Costs: Bedrock tokens per review plus Actions minutes. A monthly Bedrock budget alert in si-devops is
the backstop, and `concurrency` cancels a superseded review of the same PR.

### Setting up a caller

Nothing to configure in the repo: no secrets, no environment, no app install. Add the workflow below
and grant the three permissions, which the called job needs. The AWS role trusts `pull_request` jobs
from every `safeinsights` repo, by org name and by org ID (the immutable OIDC subject that repos
created or renamed since 2026-07-15 present), so a new repo needs no AWS change.

```yaml
name: AI code review
on:
  pull_request:
    types: [opened, ready_for_review, reopened] # add `synchronize` to re-review on every push (costs more)
permissions:
  contents: read
jobs:
  review:
    permissions:
      contents: read
      pull-requests: write
      id-token: write
    uses: safeinsights/ci-workflows/.github/workflows/ai-code-review.yaml@<commit sha> # v4.1.0
```
