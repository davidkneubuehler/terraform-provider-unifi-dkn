# Agent instructions

This repository builds a patched `filipowm/unifi` OpenTofu/Terraform provider
from the upstream tag in `UPSTREAM_VERSION` plus the patch series in
`patches/` (one directory per upstream repository), and publishes it as
GitHub releases `vX.Y.Z-dkn.N`. Read `README.md` for the build, the release
and how a root module consumes it.

Workflow: direct-main.

## Contribution cycle

- Commit validated changes on `main` and push them. Change `patches/`,
  `UPSTREAM_VERSION` and documentation (`README.md`, `AGENTS.md`) freely.
  Changes to `scripts/`, `.goreleaser.yml` and `.github/workflows/` need
  Dave's explicit request in the conversation.
- Run the release workflow (`gh workflow run release.yml --ref main`) only
  when the task asks for a release. Never delete or move a published
  `vX.Y.Z-dkn.N` tag or release: roots pin those versions and lock their
  hashes. Fix a bad release with the next `N`.
- Keep the README patch table in step with `patches/`: one row per patch with
  what it fixes and its upstream PR or issue.
- Never push to, comment on or open pull requests against
  `filipowm/terraform-provider-unifi` or `filipowm/go-unifi`, and never push
  the upstream checkouts anywhere.

## Changing the patches

- Regenerate a series from an upstream checkout in `$TMPDIR`, never by editing
  `.patch` files by hand:
  1. `scripts/prepare-source.sh "$TMPDIR/tpu-<topic>"` checks out both
     repositories and applies the series as commits. On a conflict it names
     the patch; resolve it there and `git am --continue`.
  2. Edit and commit in `go-unifi/` or `terraform-provider-unifi/`. Keep one
     commit per logical change and amend the commit a fix belongs to.
     Commit messages follow upstream's Conventional Commits style
     (`fix(user): ...`). Keep the author of a commit taken from an upstream PR.
  3. Test: `go test ./unifi/...` in go-unifi; `go vet ./...` and the unit tests
     (`go list ./... | grep -v /internal/provider/acctest | xargs go test`) in
     the provider. A fix gets a unit test that fails without it.
  4. Write the series back with
     `git format-patch --zero-commit --no-signature --base=<tag> -o <repo>/patches/<repo-name> <tag>`.
     For the provider, leave out the last commit (`build: use patched
     go-unifi`), which the script generates.
- Put a fix in the repository where the bug is: decoding of controller JSON
  belongs in go-unifi, schema and resource logic in the provider.
- Prefer an existing upstream PR over a new fix, and name it in the README.
- In the agent sandbox, Go module downloads need `storage.googleapis.com`,
  some go-unifi tests need hosts the sandbox blocks (`test.url`,
  `dl.ui.com`, `fw-update.ubnt.com`) and fail locally only, and OpenTofu
  cannot start the provider plugin (unix socket bind denied).

## Reporting

Report what changed in the series, the upstream versions it was made
against, the tests run locally and their results, and the release tag and
run when one was published.
