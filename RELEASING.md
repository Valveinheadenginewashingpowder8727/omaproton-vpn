# Releasing

`main` is what the Omarchy plugin marketplace has verified, and what
`omarchy plugin add` gives new users. It only moves at release time.

## Branches

| Branch | Purpose |
| --- | --- |
| `main` | Released code. Every commit here is (or is about to be) a verified store snapshot. Force-push and deletion are disabled. |
| `staging` | Integration. Every fix and feature merges here first and is run on a real Omarchy machine. |
| `feat/…`, `fix/…` | One change each, branched from `staging`, merged back with `--no-ff`. |

## Day to day

```bash
git checkout staging && git pull
git checkout -b fix/whatever
# … work, test in the bar (omarchy restart shell reloads Panel.qml) …
git checkout staging && git merge --no-ff fix/whatever && git push
```

Running the plugin from `staging` locally is fine — the installed folder is a
git checkout, so `git checkout staging` in
`~/.config/omarchy/plugins/io.github.grichard99.omaproton-vpn` switches it.

## Cutting a release

1. On `staging`: bump `version` in `manifest.json`, update the README if
   behaviour changed, run `omarchy plugin validate .`, test once more.
2. Merge to `main` and tag:
   ```bash
   git checkout main && git merge --no-ff staging && git push
   git tag -a vX.Y.Z -m "OmaProton VPN X.Y.Z" && git push --tags
   gh release create vX.Y.Z --title "OmaProton VPN X.Y.Z" --notes-file <notes>
   ```
3. **The store does not update itself.** Once `main` moves, the listing shows
   *Update unverified* until the new commit is verified. File the update form:
   https://github.com/HANCORE-linux/omarchy-plugin-marketplace/issues/new?template=verify-plugin.yml
   → "Verify and publish a newer upstream commit" — plugin ID
   `io.github.grichard99.omaproton-vpn`, repo URL, and the full 40-character
   SHA of `main` (`git rev-parse main`).
4. The bot validates and runs the security baseline against that commit; a
   maintainer applies `approved-and-verified`; the store swaps its snapshot.

Users on `main` get the new code as soon as it's pushed, via
`omarchy plugin update` — verification is about the store badge, not delivery.
So merge to `main` only what you would ship.

## Commits

Author and committer are the repository owner only. No co-author trailers.
