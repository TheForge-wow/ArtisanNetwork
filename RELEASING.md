# Releasing Artisan Network

Releases are built and uploaded automatically by the [BigWigs packager](https://github.com/BigWigsMods/packager). Update `## Version:` in `ArtisanNet.toc`, add a `## vX.Y.Z` section at the top of `CHANGELOG.md`, commit, and push a tag with the version number (e.g. `1.6.8`). That section becomes the CurseForge changelog for the upload.

Repository secrets used: `CF_API_KEY` (required for CurseForge), `WAGO_API_TOKEN` (optional).

## Publish button (no chat needed)
Actions tab → **Package and release** → **Run workflow**. Enter the version (it must match `## Version:` in the .toc and have a `## vX.Y.Z` section in `CHANGELOG.md`). Untick **Upload to CurseForge** to release to Wago only, for example to put a version that's already on CurseForge onto Wago.
