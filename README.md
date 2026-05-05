# bella-baxter-setup-action

Install the [Bella CLI](https://bella-baxter.io) on your GitHub Actions runner — Linux, macOS, or Windows. Self-contained binary with zero runtime dependencies (no Node.js, no .NET, no package manager).

```yaml
- uses: cosmic-chimps/bella-baxter-setup-action@v0.1.1-preview.82
```

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `version` | No | `latest` | CLI version to install, e.g. `1.2.3`. Omit for the latest release. |
| `bella-url` | No | — | Your Bella Baxter API base URL. When provided, exported as `BELLA_BAXTER_URL` for all subsequent steps in the job. |

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

      - uses: cosmic-chimps/bella-baxter-setup-action@v0.1.1-preview.82
        with:
          bella-url: ${{ vars.BELLA_BAXTER_URL }}

      - run: bella login --api-key ${{ secrets.BELLA_BAXTER_API_KEY }}

      - run: bella exec -p my-api -e production -- ./deploy.sh
```

## Authentication

### API Key

```yaml
- uses: cosmic-chimps/bella-baxter-setup-action@v0.1.1-preview.82
  with:
    bella-url: ${{ vars.BELLA_BAXTER_URL }}

- run: bella login --api-key ${{ secrets.BELLA_BAXTER_API_KEY }}
```

Store your API key as a GitHub Actions secret (`BELLA_BAXTER_API_KEY`). Get one from the Bella Baxter WebApp → **Settings → API Keys**.

### Keyless — Trust Domain (Recommended for CI/CD)

No stored credentials. Uses GitHub's OIDC token. Requires a [Trust Domain](https://bella-baxter.io/features/keyless) configured for your repository.

```yaml
permissions:
  id-token: write   # required

steps:
  - uses: cosmic-chimps/bella-baxter-setup-action@v0.1.1-preview.82
    with:
      bella-url: ${{ vars.BELLA_BAXTER_URL }}

  - run: bella run -p my-api -e production -- ./deploy.sh
```

## Usage Patterns

### Inject secrets as environment variables

`bella exec` wraps your command and injects all secrets. Nothing is written to disk.

```yaml
- uses: cosmic-chimps/bella-baxter-setup-action@v0.1.1-preview.82
  with:
    bella-url: ${{ vars.BELLA_BAXTER_URL }}

- run: bella login --api-key ${{ secrets.BELLA_BAXTER_API_KEY }}
- run: bella exec -p my-api -e production -- ./deploy.sh
```

### SSH certificate signing

Issue a short-lived SSH certificate via Bella's SSH CA:

```yaml
- uses: cosmic-chimps/bella-baxter-setup-action@v0.1.1-preview.82
  with:
    bella-url: ${{ vars.BELLA_BAXTER_URL }}

- run: bella login --api-key ${{ secrets.BELLA_BAXTER_API_KEY }}
- run: bella ssh sign ~/.ssh/id_ed25519.pub --role deployer
- run: ssh -i ~/.ssh/id_ed25519-cert.pub deploy@prod ./deploy.sh
```

### Generate and rotate a secret

`bella generate` is fully offline (pure crypto — no API call):

```yaml
- uses: cosmic-chimps/bella-baxter-setup-action@v0.1.1-preview.82
  with:
    bella-url: ${{ vars.BELLA_BAXTER_URL }}

- run: bella login --api-key ${{ secrets.BELLA_BAXTER_API_KEY }}
- run: |
    NEW_PASS=$(bella generate --length 32 --quiet)
    bella secrets set DB_PASSWORD "$NEW_PASS" -p my-api -e production
```

### AI Agent Workflows (MCP)

For GitHub Copilot coding agent or custom AI pipelines, `bella mcp` exposes secrets, TOTP, SSH signing, and token issuance as MCP tools:

```yaml
- uses: cosmic-chimps/bella-baxter-setup-action@v0.1.1-preview.82
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
- uses: cosmic-chimps/bella-baxter-setup-action@v0.1.1-preview.82
  with:
    version: '1.2.3'          # CLI binary version (from GitHub Releases)
    bella-url: ${{ vars.BELLA_BAXTER_URL }}
```

## Supported Platforms

| Runner | Architecture | Supported |
|--------|-------------|-----------|
| `ubuntu-*` | x64, arm64 | ✅ |
| `macos-*` | x64 (Intel), arm64 (Apple Silicon) | ✅ |
| `windows-*` | x64, arm64 | ✅ |

## License

[Apache 2.0](https://github.com/Cosmic-Chimps/bella-baxter/blob/main/LICENSE)
