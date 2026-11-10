# Releasing

Releases are Git tags named `vMAJOR.MINOR.PATCH`, following [Semantic Versioning](https://semver.org/). The AWS and Azure configurations share one version. Each release has a section in [CHANGELOG.md](CHANGELOG.md) and a GitHub release.

## Choose the version

- **Major:** users must act before they apply, for example a removed variable or a higher provider minimum.
- **Minor:** a new feature that applies without changes.
- **Patch:** a fix.

Before 1.0.0, a breaking change bumps the minor version, and everything else bumps the patch version.

## Release steps

1. On an up-to-date `main`, check that CI passes and run `just lint`, `just validate`, and `just test`.
2. In `CHANGELOG.md`, rename `## Unreleased` to `## [X.Y.Z] - YYYY-MM-DD`, then add a new empty `## Unreleased` section above it.
3. Set `LAUNCHER_VERSION` in `aws/lambda_function.py` to `X.Y.Z`. Scalr shows it on the agent pool and warns about older launchers.
4. Commit the changelog and the version as `Release vX.Y.Z` through a pull request, and merge it.
5. Tag the merge commit on `main` and push the tag:

   ```shell
   git switch main && git pull
   git tag -a vX.Y.Z -m "vX.Y.Z"
   git push origin vX.Y.Z
   ```

6. Create the GitHub release from the tag, with the changelog section as its notes:

   ```shell
   gh release create vX.Y.Z --title vX.Y.Z --notes-file {notes_file}
   ```

   `{notes_file}` holds the entries of the `## [X.Y.Z]` section, without its heading.

Never move or delete a pushed tag. To fix a release, publish a new patch version.
