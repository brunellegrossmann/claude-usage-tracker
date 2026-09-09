# Releasing

Pushing a `v*` tag builds the app, signs the download, attests its provenance, and publishes a GitHub Release with the zip attached.
No Apple Developer account, certificate, or notarization is involved, and no Apple secrets exist in CI.

## One-time setup

### 1. Release signing key (optional today)

Releases work without this.
The workflow signs the download when the secret exists and warns and continues when it does not, because nothing verifies the signature yet - the build provenance attestation is the check users actually run.
Set it up when you want it, and it becomes required once the in-app updater ships, since that verifies the signature before installing.

Generate the key pair once:

```sh
swift Scripts/release_signing.swift generate
```

It prints the **public** key and writes the private key to `./release-signing-private-key.txt` (mode 600).
Then:

```sh
gh secret set RELEASE_SIGNING_PRIVATE_KEY < release-signing-private-key.txt
rm release-signing-private-key.txt
```

Put the printed public key in `Resources/Info.plist` under `ReleaseSigningPublicKey`; that is what the in-app updater will check signatures against.
The private key must never be committed, pasted into a terminal that keeps scrollback, or stored anywhere but the repo secret and your password manager.

Lose it and future updates cannot be signed (recover by generating a new pair and shipping a build that embeds the new public key, which every older install must be updated to manually).
Leak it and anyone can sign a build that passes the signature check.

### 2. GitHub Pages (pricing feed)

**Settings ▸ Pages ▸ Source: Deploy from a branch**, branch `main`, folder `/docs`.
Verify:

```sh
curl -sSI https://brunellegrossmann.github.io/claude-usage-tracker/pricing.json | head -1
```

Until this is enabled every app silently falls back to its bundled prices.
See [`docs/PRICING_FEED.md`](docs/PRICING_FEED.md).

## Cutting a release

1. Update `CHANGELOG.md` if the repo has one, and make sure `docs/pricing.json` is current.
2. Tag and push:

   ```sh
   git tag -a v1.2.0 -m "v1.2.0"
   git push origin v1.2.0
   ```

3. Wait for the **Release** workflow.
4. Verify the published download the way a user would:

   ```sh
   gh release download v1.2.0 -R brunellegrossmann/claude-usage-tracker
   gh attestation verify Claude-Code-Usage-v1.2.0.zip -R brunellegrossmann/claude-usage-tracker
   shasum -a 256 -c checksums.txt
   ```

5. Check that the release notes render and that the zip unpacks to a launchable app.

The version users see comes from the tag: `build.sh` stamps `CFBundleShortVersionString` from `APP_VERSION`, and the in-app update check compares the running version against the latest release tag.
A tag that does not increase the version will not be offered as an update.

## What the workflow produces

| Asset | Purpose |
|---|---|
| `Claude-Code-Usage-vX.Y.Z.zip` | The app bundle, ad-hoc signed, not notarized. |
| `Claude-Code-Usage-vX.Y.Z.zip.sig` | Ed25519 signature over the zip. Only present when `RELEASE_SIGNING_PRIVATE_KEY` is set. Checked manually today (`release_signing.swift verify`), and by the in-app updater once it ships. |
| `claude-code-usage.rb` | The Homebrew cask for this version, ready to copy into the tap. |
| `checksums.txt` | SHA-256 of the zip, for a manual check. |
| Build provenance attestation | Sigstore statement that this zip came from this workflow and commit. Not a file: `gh attestation verify` fetches it. |

The checksum alone proves nothing against a compromised release: whoever can replace the zip can replace the checksum.
The signature and the attestation are the parts that carry weight.

## Homebrew tap

Homebrew can only tap a repo named `homebrew-*`, so the cask lives in a separate repo rather than this one.

One-time:

1. Create a public repo `brunellegrossmann/homebrew-tap`.
2. Add a `Casks/` directory.

Per release, the workflow attaches the finished cask as `claude-code-usage.rb`:

```sh
gh release download vX.Y.Z -R brunellegrossmann/claude-usage-tracker -p claude-code-usage.rb
# then in the tap repo:
mv claude-code-usage.rb Casks/claude-code-usage.rb
git commit -am "claude-code-usage vX.Y.Z" && git push
```

Users then install and, more importantly, **update** with:

```sh
brew tap brunellegrossmann/tap
brew install --cask --no-quarantine claude-code-usage
brew upgrade --cask claude-code-usage
```

`--no-quarantine` matters: Homebrew quarantines downloaded apps by default, and an unsigned app hits the Gatekeeper dialog without it.
`brew upgrade` is the update path that needs no in-app updater at all.

## If the release workflow fails

- **Attestation step fails** - the workflow needs `id-token: write` and `attestations: write` permissions, and the repo must be public for the attestation to be publicly verifiable.
- **Build fails** - fix it on `main` and move the tag; do not hand-edit a published release.
