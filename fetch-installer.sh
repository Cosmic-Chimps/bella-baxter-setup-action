#!/usr/bin/env bash
# Fetches the Bella CLI installer FROM THE RELEASE IT INSTALLS and verifies it before anything runs it
# (#828). It used to be piped straight from bella-baxter-cli's `main` branch, so pinning this Action by
# tag or SHA pinned nothing that executed.
#
#   1. Resolve the version: the `version` input, else the release `releases/latest` redirects to.
#   2. Download, from that release only: checksums.txt, its detached signature checksums.txt.asc, the
#      public key bella-signing-key.asc, and the installer (install-bella.sh / install-bella.ps1).
#   3. Verify the signature in a throwaway GNUPGHOME and accept it ONLY when gpg reports VALIDSIG for
#      the primary fingerprint pinned below. The downloaded key is transport, not trust: whatever it
#      contains, nothing but a signature by the pinned key passes, and this file is pinned by the ref
#      the workflow uses for the Action.
#   4. Check the installer's SHA-256 against the now-authenticated checksums.txt.
# Any failure aborts. The single opt-out is BELLA_INSECURE_SKIP_SIGNATURE=1 (air-gapped mirrors).
#
# Inputs (env): BELLA_INSTALL_VERSION, RUNNER_OS, RUNNER_TEMP, GITHUB_OUTPUT.
# Outputs: version, installer (path of the verified installer, in the runner's native path form).

set -euo pipefail

REPO="Cosmic-Chimps/bella-baxter-cli"
# Must equal SIGNING_FINGERPRINT in apps/cli-dotnet/scripts/install-bella.{sh,ps1}.
SIGNING_FINGERPRINT="65BB8D3CEEE3DD9E4FFD22B4119F114CA309C2FA"

die()  { echo "::error::$*" >&2; exit 1; }
warn() { echo "::warning::$*" >&2; }

insecure=0
if [ "${BELLA_INSECURE_SKIP_SIGNATURE:-0}" = "1" ]; then
  insecure=1
  warn "BELLA_INSECURE_SKIP_SIGNATURE=1 — the release signature is NOT verified. The installer is checked against checksums.txt only, which proves integrity, NOT that Cosmic Chimps published it. Use only for air-gapped mirrors."
fi

# ── 1. Version ────────────────────────────────────────────────────────────────
version="${BELLA_INSTALL_VERSION:-latest}"
version="${version#v}"
if [ -z "$version" ] || [ "$version" = "latest" ]; then
  # The redirect needs no API call, so it is not subject to the anonymous API rate limit.
  effective=$(curl -sSfL -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest") \
    || die "Could not resolve the latest Bella CLI release."
  version="${effective##*/tag/}"
  version="${version#v}"
fi
printf '%s' "$version" | grep -Eq '^[0-9A-Za-z][0-9A-Za-z.+-]*$' \
  || die "Invalid Bella CLI version '${version}'."
echo "Bella CLI version: ${version}"

# ── 2. Download from that release ─────────────────────────────────────────────
if [ "${RUNNER_OS:-}" = "Windows" ]; then installer_name="install-bella.ps1"; else installer_name="install-bella.sh"; fi
base_url="https://github.com/${REPO}/releases/download/v${version}"

work="${RUNNER_TEMP:?RUNNER_TEMP is not set}/bella-installer"
if command -v cygpath >/dev/null 2>&1; then work="$(cygpath -u "$work")"; fi   # Git Bash on Windows
rm -rf "$work"
mkdir -p "$work"

fetch() { curl -sSfL --retry 3 -o "$2" "$1"; }

fetch "${base_url}/checksums.txt" "$work/checksums.txt" \
  || die "Release v${version} has no checksums.txt — is '${version}' a published Bella CLI version?"

installer="$work/${installer_name}"
if ! fetch "${base_url}/${installer_name}" "$installer"; then
  if [ "$insecure" = "1" ]; then
    # Releases made before #828 do not publish the installer as an asset. The tag's own copy is at
    # least pinned to that release, but nothing vouches for it — and it predates fail-closed checks.
    warn "Release v${version} does not publish ${installer_name}; using the copy in the v${version} tag, UNVERIFIED."
    fetch "https://raw.githubusercontent.com/${REPO}/v${version}/scripts/${installer_name}" "$installer" \
      || die "Could not download ${installer_name} for v${version}."
  else
    die "Release v${version} does not publish ${installer_name} as a signed release asset (releases made before #828 do not), so the installer cannot be verified. Use a newer 'version', or — air-gapped mirrors only — set BELLA_INSECURE_SKIP_SIGNATURE=1."
  fi
else
  # ── 3. Authenticate checksums.txt ───────────────────────────────────────────
  if [ "$insecure" = "0" ]; then
    command -v gpg >/dev/null 2>&1 \
      || die "gpg is required to verify the Bella CLI release signature and was not found on this runner. Install GnuPG, or — air-gapped mirrors only — set BELLA_INSECURE_SKIP_SIGNATURE=1."
    fetch "${base_url}/checksums.txt.asc" "$work/checksums.txt.asc" \
      || die "Release v${version} publishes no checksums.txt.asc — refusing an unsigned release."
    fetch "${base_url}/bella-signing-key.asc" "$work/bella-signing-key.asc" \
      || die "Release v${version} publishes no bella-signing-key.asc — cannot verify its signature."

    gnupg_home="$work/gnupg"
    mkdir -p "$gnupg_home"
    chmod 700 "$gnupg_home"
    gpg --homedir "$gnupg_home" --batch --quiet --import "$work/bella-signing-key.asc" >/dev/null 2>&1 \
      || die "Could not import bella-signing-key.asc from release v${version}."
    status=$(gpg --homedir "$gnupg_home" --batch --status-fd 1 \
               --verify "$work/checksums.txt.asc" "$work/checksums.txt" 2>/dev/null) || status=""
    gpgconf --homedir "$gnupg_home" --kill all >/dev/null 2>&1 || true
    # VALIDSIG's LAST field is the fingerprint of the PRIMARY key that made the signature.
    printf '%s\n' "$status" | awk -v fpr="$SIGNING_FINGERPRINT" \
        '$1 == "[GNUPG:]" && $2 == "VALIDSIG" && $NF == fpr { found = 1 } END { exit found ? 0 : 1 }' \
      || die "GPG signature verification FAILED for release v${version}: checksums.txt is not signed by the Cosmic Chimps release key ${SIGNING_FINGERPRINT}. This may indicate tampering."
    echo "GPG signature verified (key ${SIGNING_FINGERPRINT})"
  fi

  # ── 4. Check the installer against it ───────────────────────────────────────
  expected=$(awk -v name="$installer_name" '{ n = $2; sub(/^\*/, "", n); if (n == name) { print $1; exit } }' "$work/checksums.txt")
  [ -n "$expected" ] || die "checksums.txt of v${version} lists no ${installer_name}."
  if command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum "$installer" | awk '{print $1}')
  else
    actual=$(shasum -a 256 "$installer" | awk '{print $1}')
  fi
  [ "$expected" = "$actual" ] \
    || die "${installer_name} does not match checksums.txt (expected ${expected}, got ${actual}). This may indicate tampering."
  echo "${installer_name} verified against checksums.txt"
fi

if command -v cygpath >/dev/null 2>&1; then installer="$(cygpath -w "$installer")"; fi
{
  echo "version=${version}"
  echo "installer=${installer}"
} >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set}"
