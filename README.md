# bella-baxter-setup-action

Install the [Bella CLI](https://bella-baxter.io) on your GitHub Actions runner — Linux, macOS, or Windows. Self-contained binary with zero runtime dependencies (no Node.js, no .NET, no package manager).

```yaml
- uses: cosmic-chimps/bella-baxter-setup-action@v0.1.1-preview.142
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `version` | No | `latest` | CLI version to install, e.g. `1.2.3`. Omit for the latest release. |
| `bella-url` | No | `https://api.bella-baxter.io` (OIDC step only) | Your Bella Baxter **API** base URL. Self-hosted: your API origin, not the console's. When provided, exported as `BELLA_BAXTER_URL` for all subsequent steps in the job. |
| `oidc` | No | `false` | `true` exchanges the job's GitHub OIDC token for a short-lived Bella API key. Needs `permissions: id-token: write`, a Trust Domain on the environment, and `tenant`, `project` and `environment`. The key is exported, masked, as `BELLA_BAXTER_API_KEY` (and the legacy alias `BELLA_API_KEY`) for all later steps in the job. Its device key is exported too, masked, as `BELLA_BAXTER_PRIVATE_KEY`; no new input is needed. |
| `tenant` | With `oidc` | — | Tenant (organisation) slug. Falls back to `BELLA_BAXTER_TENANT` in the job's `env`. |
| `project` | With `oidc` | — | Project slug. Falls back to `BELLA_BAXTER_PROJECT`. |
| `environment` | With `oidc` | — | Environment slug. Falls back to `BELLA_BAXTER_ENV`. |
| `audience` | No | `bella-baxter` | OIDC audience to request. Must be one the Trust Domain accepts. Falls back to `BELLA_OIDC_AUDIENCE`, then the default. |

The `tenant`, `project`, `environment` and `audience` inputs are read only when `oidc` is `true`. An input overrides the job-level variable of the same purpose only when it is non-empty. The step fails early, with an error naming what is missing, if a slug is still empty (a committed `.bella` file with org, project and environment also satisfies it).

## Outputs

| Output | Description |
|--------|-------------|
| `bella-version` | The installed Bella CLI version string. |

## Quick Start

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6

      - uses: cosmic-chimps/bella-baxter-setup-action@v0.1.1-preview.142
        with:
          bella-url: ${{ vars.BELLA_BAXTER_URL }}

      # The CLI reads BELLA_BAXTER_API_KEY from the environment. A key passed as a command
      # argument is visible in the runner's process list and in its command log (#833).
      - run: bella exec -p my-api -e production -- ./deploy.sh
        env:
          BELLA_BAXTER_API_KEY: ${{ secrets.BELLA_BAXTER_API_KEY }}
```

## Authentication

### API Key

```yaml
- uses: cosmic-chimps/bella-baxter-setup-action@v0.1.1-preview.142
  with:
    bella-url: ${{ vars.BELLA_BAXTER_URL }}

# The CLI reads BELLA_BAXTER_API_KEY from the environment. A key passed as a command
# argument is visible in the runner's process list and in its command log (#833).
# Declare it as job or step env:
#   env:
#     BELLA_BAXTER_API_KEY: ${{ secrets.BELLA_BAXTER_API_KEY }}
```

Store your API key as a GitHub Actions secret (`BELLA_BAXTER_API_KEY`). Get one from the Bella Baxter WebApp → **Settings → API Keys**.

### Keyless — Trust Domain (Recommended for CI/CD)

No stored credentials. Uses GitHub's OIDC token. Requires a [Trust Domain](https://bella-baxter.io/features/keyless) on the environment (console, environment, **Identity** tab) whose claim rules match your repository.

```yaml
permissions:
  id-token: write   # required to get GitHub's OIDC token
  contents: read

steps:
  - uses: actions/checkout@v6

  - uses: cosmic-chimps/bella-baxter-setup-action@v0.1.1-preview.142
    with:
      bella-url: ${{ vars.BELLA_BAXTER_URL }}   # optional; default https://api.bella-baxter.io
      oidc: 'true'
      tenant: my-org
      project: my-api
      environment: production

  # BELLA_BAXTER_API_KEY is now set (masked) and scoped to that environment,
  # so no -p / -e is needed.
  - run: bella run -- ./deploy.sh
```

Notes:

- `bella-url` is the **API** origin (`https://api.bella-baxter.io` for the hosted service), not the console's.
- **Tenants that require registered devices (ZKE).** Each sign-in makes a new device key and sends its public half. The server records it on the issued key, and the device check admits the key only when the caller presents that same public half. The action exports the private half, masked, as `BELLA_BAXTER_PRIVATE_KEY` next to the API key, so later steps need no key options: `bella run -- ./deploy.sh` finds it. A tenant that does not require devices accepts the key either way.
  - The private half is bound to one API key, which expires with the Trust Domain's token lifetime (15 minutes by default, 1 to 1440). Exposing it is no worse than exposing that key, and it is useless afterwards.
  - It is masked before it is written to `$GITHUB_ENV`, every line of the PEM included. Do not print it.
  - It needs a current CLI. An older one sends no device key, and a tenant that requires devices refuses the sign-in with `device_key_required`.
- If the Trust Domain accepts a different audience, add `audience: <value>` (or set `BELLA_OIDC_AUDIENCE`). It must be one the Trust Domain accepts.
- `bella run` does not mask the secret values it injects into the child process. Don't echo them in the step; if a script prints one, register it first with `echo "::add-mask::$VALUE"`. There is no rename option, so map a secret to another name in the step: `MY_VAR="$BELLA_NAME" ./deploy.sh`.

## Usage Patterns

### Inject secrets as environment variables

`bella exec` wraps your command and injects all secrets. Nothing is written to disk.

```yaml
- uses: cosmic-chimps/bella-baxter-setup-action@v0.1.1-preview.142
  with:
    bella-url: ${{ vars.BELLA_BAXTER_URL }}

# The CLI reads BELLA_BAXTER_API_KEY from the environment. A key passed as a command
# argument is visible in the runner's process list and in its command log (#833).
- run: bella exec -p my-api -e production -- ./deploy.sh
  env:
    BELLA_BAXTER_API_KEY: ${{ secrets.BELLA_BAXTER_API_KEY }}
```

### SSH certificate signing

Issue a short-lived SSH certificate via Bella's SSH CA:

```yaml
- uses: cosmic-chimps/bella-baxter-setup-action@v0.1.1-preview.142
  with:
    bella-url: ${{ vars.BELLA_BAXTER_URL }}

# The CLI reads BELLA_BAXTER_API_KEY from the environment. A key passed as a command
# argument is visible in the runner's process list and in its command log (#833).
- run: bella ssh sign ~/.ssh/id_ed25519.pub --role deployer
  env:
    BELLA_BAXTER_API_KEY: ${{ secrets.BELLA_BAXTER_API_KEY }}
- run: ssh -i ~/.ssh/id_ed25519-cert.pub deploy@prod ./deploy.sh
```

### Generate and rotate a secret

`bella generate` is fully offline (pure crypto — no API call):

```yaml
- uses: cosmic-chimps/bella-baxter-setup-action@v0.1.1-preview.142
  with:
    bella-url: ${{ vars.BELLA_BAXTER_URL }}

# The CLI reads BELLA_BAXTER_API_KEY from the environment. A key passed as a command
# argument is visible in the runner's process list and in its command log (#833).
- env:
    BELLA_BAXTER_API_KEY: ${{ secrets.BELLA_BAXTER_API_KEY }}
  run: |
    NEW_PASS=$(bella generate --length 32 --quiet)
    bella secrets set DB_PASSWORD "$NEW_PASS" -p my-api -e production
```

### AI Agent Workflows (MCP)

For GitHub Copilot coding agent or custom AI pipelines, `bella mcp` exposes secrets, TOTP, SSH signing, and token issuance as MCP tools:

```yaml
- uses: cosmic-chimps/bella-baxter-setup-action@v0.1.1-preview.142
  with:
    bella-url: ${{ vars.BELLA_BAXTER_URL }}

- run: echo "BELLA_BAXTER_API_KEY=${{ secrets.BELLA_BAXTER_API_KEY }}" >> $GITHUB_ENV
# Your AI agent runner launches: bella mcp
```

Print the MCP config snippet for Claude Desktop or VS Code:

```bash
bella mcp --print-config
```

## Pin a specific version

```yaml
# Pin both the action version and the CLI binary version independently
- uses: cosmic-chimps/bella-baxter-setup-action@v0.1.1-preview.142
  with:
    version: '1.2.3'          # CLI binary version (from GitHub Releases)
    bella-url: ${{ vars.BELLA_BAXTER_URL }}
```

## What the action verifies

The ref you pin (`@v…`, or better a full commit SHA) is the code that installs the CLI. The action
does not run anything from a branch. When it runs, it:

1. Resolves the CLI version: the `version` input, or the release that `latest` points to.
2. Downloads that release's `checksums.txt`, `checksums.txt.asc`, `bella-signing-key.asc` and the
   installer (`install-bella.sh` or `install-bella.ps1`). All of them are assets of that one release.
3. Verifies the signature in a throwaway GnuPG home. It accepts the signature only when it was made by
   the Cosmic Chimps release key with fingerprint `65BB 8D3C EEE3 DD9E 4FFD 22B4 119F 114C A309 C2FA`,
   which is pinned in the action itself.
4. Checks the installer's SHA-256 against that signed file, then runs the installer with the resolved
   version. The installer repeats both checks for the binary, using its own embedded copy of the key.

Every failure stops the job. `gpg` must be on the runner; it is on GitHub-hosted Ubuntu and macOS
images, and ships with Git for Windows. Only CLI releases that publish their installer as an asset
can be installed this way, and earlier releases are refused. For an air-gapped mirror that cannot
carry the signature, set `BELLA_INSECURE_SKIP_SIGNATURE: '1'` in the job's `env`. The installer is then
checked against `checksums.txt` only, and the log shows a warning.

## Supported Platforms

| Runner | Architecture | Supported |
|--------|-------------|-----------|
| `ubuntu-*` | x64, arm64 | ✅ |
| `macos-*` | x64 (Intel), arm64 (Apple Silicon) | ✅ |
| `windows-*` | x64, arm64 | ✅ |

## License

[Apache 2.0](https://github.com/Cosmic-Chimps/bella-baxter/blob/main/LICENSE)
