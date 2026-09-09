# Releasing

Pushing a `v*` tag builds the app, signs the download, attests its provenance, and publishes a GitHub Release with the zip attached.
No Apple Developer account, certificate, or notarization is involved, and no Apple secrets exist in CI.

## One-time setup

### 1. Release signing key

Every release download is signed with an Ed25519 key, so an attacker who controls the download server cannot forge a build.
The key is set up now so releases are signed from the first one; the in-app updater that checks the signature automatically ships separately.
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
| `Claude-Code-Usage-vX.Y.Z.zip.sig` | Ed25519 signature over the zip. Checked manually today (`release_signing.swift verify`), and by the in-app updater once it ships. |
| `checksums.txt` | SHA-256 of the zip, for a manual check. |
| Build provenance attestation | Sigstore statement that this zip came from this workflow and commit. Not a file: `gh attestation verify` fetches it. |

The checksum alone proves nothing against a compromised release: whoever can replace the zip can replace the checksum.
The signature and the attestation are the parts that carry weight.

## If the release workflow fails

- **`RELEASE_SIGNING_PRIVATE_KEY is not set`** - the secret is missing. The workflow refuses to publish an unsigned download rather than shipping one the app cannot verify.
- **Attestation step fails** - the workflow needs `id-token: write` and `attestations: write` permissions, and the repo must be public for the attestation to be publicly verifiable.
- **Build fails** - fix it on `main` and move the tag; do not hand-edit a published release.
