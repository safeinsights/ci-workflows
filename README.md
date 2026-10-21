# ci-workflows

Shared GitHub Actions workflows for SafeInsights repos. They replace the Jenkins shared library
(SHRMP-343).

| Workflow | What it does |
|---|---|
| [`harbor-image.yaml`](.github/workflows/harbor-image.yaml) | Builds a Docker image on every run and pushes it to Harbor only on `main` |
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
uses: safeinsights/ci-workflows/.github/workflows/harbor-image.yaml@<commit sha> # v1.0.0
```

Release by tagging `main` with a semver tag (`v1.0.0`, ...). A change to the inputs that would
break existing callers needs a new major version.

## `harbor-image.yaml`

Pushes only when `push` is true (the default), the event is not a pull request, and the ref is
`main`. Anything else just builds, so a broken Dockerfile still fails the PR.

| Input | Default | Notes |
|---|---|---|
| `image` | required | e.g. `harbor.safeinsights.org/openstax/r-base` |
| `tag` | required | Template: `{date}` (UTC `YYYY-MM-DD`), `{sha}`, `{sha8}`, e.g. `4.5.1-{date}-{sha8}` |
| `context` | `.` | Build context in the caller's repo |
| `file` | `<context>/Dockerfile` | |
| `platforms` | `linux/amd64` | |
| `push` | `true` | `false` never pushes |
| `timeout-minutes` | `90` | |

Secrets: `HARBOR_USERNAME` and `HARBOR_TOKEN` (needed only when pushing). Output: `image-ref`.

```yaml
jobs:
  build:
    strategy:
      fail-fast: false
      matrix:
        include:
          - { dir: python-3.12, image: openstax/python-base, tag: '3.12-{date}-{sha8}' }
          - { dir: r-4.5.1, image: openstax/r-base, tag: '4.5.1-{date}-{sha8}' }
    uses: safeinsights/ci-workflows/.github/workflows/harbor-image.yaml@<commit sha> # v1.0.0
    with:
      image: harbor.safeinsights.org/${{ matrix.image }}
      tag: ${{ matrix.tag }}
      context: ${{ matrix.dir }}
    secrets:
      HARBOR_USERNAME: ${{ secrets.HARBOR_USERNAME }}
      HARBOR_TOKEN: ${{ secrets.HARBOR_TOKEN }}
```

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
    uses: safeinsights/ci-workflows/.github/workflows/sonarqube.yaml@<commit sha> # v1.0.0
    with:
      coverage-artifact: python-coverage
      coverage-path: python-3.12
    secrets:
      SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
      SONAR_HOST_URL: ${{ secrets.SONAR_HOST_URL }}
```

## Testing changes

`self-test.yaml` runs actionlint and builds `tests/fixtures/hello` through `harbor-image.yaml`
on every PR, without pushing. Locally: `actionlint` from the repo root.
