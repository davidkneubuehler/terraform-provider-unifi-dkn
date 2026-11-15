# terraform-provider-unifi-dkn

An unofficial build of the
[filipowm/unifi](https://github.com/filipowm/terraform-provider-unifi)
OpenTofu/Terraform provider with a few patches on top. The upstream project
does not support it.

Upstream base: provider [`v1.1.0`](https://github.com/filipowm/terraform-provider-unifi/releases/tag/v1.1.0)
(set in [`UPSTREAM_VERSION`](UPSTREAM_VERSION)), built against the
[filipowm/go-unifi](https://github.com/filipowm/go-unifi) release its `go.mod`
requires (`v1.9.3` for provider `v1.1.0`).

## Patches

[`patches/go-unifi/`](patches/go-unifi) applies to go-unifi,
`patches/terraform-provider-unifi/` (none yet) to the provider.

| Patch | What it does | Upstream |
| --- | --- | --- |
| `go-unifi/0001-fix-user-decode-dev_id_override-sent-as-a-string-by-.patch` | UniFi Network 11 (seen on 11.0.99) returns a client's `dev_id_override` (the icon set in the UniFi app) as a numeric string such as `"3263"`; earlier versions sent a number. go-unifi decoded it as `int`, so reading any `unifi_user` with an icon failed with `cannot unmarshal string into Go struct field .Alias.dev_id_override of type int`. The field now decodes from a number, a numeric string, `""` or `null`. Writes still send a number. Includes `TestUserUnmarshalDevIdOverride`. | The commit of [filipowm/go-unifi#200](https://github.com/filipowm/go-unifi/pull/200) by Ross McKelvie, unchanged (backport of [filipowm/go-unifi#199](https://github.com/filipowm/go-unifi/pull/199)); open upstream |

Drop a patch once the upstream release in `UPSTREAM_VERSION` contains it.

## Releases

Release `vX.Y.Z-dkn.N` is revision `N` of upstream provider `vX.Y.Z`. Each
release carries the files the provider registries use:

- `terraform-provider-unifi_X.Y.Z-dkn.N_<os>_<arch>.zip` for `darwin_amd64`,
  `darwin_arm64`, `linux_amd64` and `linux_arm64`, each holding the single
  binary `terraform-provider-unifi_vX.Y.Z-dkn.N`;
- `terraform-provider-unifi_X.Y.Z-dkn.N_SHA256SUMS` with the zips' SHA-256.

The zips and the checksum file have a GitHub build provenance attestation
(keyless, Sigstore). Verify a download with:

```sh
sha256sum -c --ignore-missing terraform-provider-unifi_1.1.0-dkn.1_SHA256SUMS
gh attestation verify terraform-provider-unifi_1.1.0-dkn.1_darwin_arm64.zip \
  -R davidkneubuehler/terraform-provider-unifi-dkn
```

## Using a release

The release keeps the provider address `filipowm/unifi`, so existing state and
configuration need no `replace-provider`. The version `1.1.0-dkn.1` exists only
here, and OpenTofu installs a prerelease version only on an exact constraint:

```hcl
terraform {
  required_providers {
    unifi = {
      source  = "filipowm/unifi"
      version = "1.1.0-dkn.1"
    }
  }
}
```

GitHub releases cannot serve the network mirror protocol, so install the zips
into a filesystem mirror in the packed layout,
`<mirror>/registry.opentofu.org/filipowm/unifi/terraform-provider-unifi_<version>_<os>_<arch>.zip`:

```sh
version=1.1.0-dkn.1
mirror=$HOME/.terraform.d/mirror   # any directory
dir=$mirror/registry.opentofu.org/filipowm/unifi
mkdir -p "$dir"
gh release download "v$version" -R davidkneubuehler/terraform-provider-unifi-dkn \
  -D "$dir" -p "terraform-provider-unifi_${version}_*"
(cd "$dir" && sha256sum -c --ignore-missing "terraform-provider-unifi_${version}_SHA256SUMS")
```

and point the CLI configuration (`~/.tofurc`, or the file in
`TF_CLI_CONFIG_FILE`) at it for this provider only:

```hcl
provider_installation {
  filesystem_mirror {
    path    = "/Users/you/.terraform.d/mirror"
    include = ["registry.opentofu.org/filipowm/unifi"]
  }
  direct {
    exclude = ["registry.opentofu.org/filipowm/unifi"]
  }
}
```

Then `tofu init -upgrade`. To record hashes for more platforms in
`.terraform.lock.hcl`, run
`tofu providers lock -fs-mirror="$mirror" -platform=darwin_arm64 -platform=linux_amd64`.
A filesystem mirror yields `h1:` hashes only.

## How a release is built

[`.github/workflows/release.yml`](.github/workflows/release.yml):

1. [`scripts/prepare-source.sh`](scripts/prepare-source.sh) clones the provider
   at `UPSTREAM_VERSION` and applies `patches/terraform-provider-unifi/`, then
   clones the go-unifi version from the provider's `go.mod`, applies
   `patches/go-unifi/` and commits a `replace github.com/filipowm/go-unifi =>
   ../go-unifi` into the provider checkout. Each series applies with
   `git am -3`.
2. It runs `go test ./unifi/...` in go-unifi and `go vet` plus the unit tests
   in the provider. The acceptance tests need a UniFi controller in Docker and
   do not run.
3. It builds the zips and the checksum file with GoReleaser
   ([`.goreleaser.yml`](.goreleaser.yml)).

Pushes and pull requests stop there. A manual run on `main` picks the next
`N`, or stops if the newest `vX.Y.Z-dkn.N` already has the current
`UPSTREAM_VERSION`, `patches/`, `scripts/` and `.goreleaser.yml` (use the
`force` input to publish anyway), and then attests the files and creates the
release with its tag on the commit that was built:

```sh
gh workflow run release.yml --ref main -R davidkneubuehler/terraform-provider-unifi-dkn
```

## Working on the patches

The series are `git format-patch` output made against upstream tags. To change
them or carry them to a new upstream release, set `UPSTREAM_VERSION` and run:

```sh
work=$(mktemp -d)/src
scripts/prepare-source.sh "$work"
```

If a patch does not apply, the script names it and leaves `git am` stopped in
that checkout: resolve the conflicts, `git add` them and run
`git am --continue`. Edit and commit in `$work/go-unifi` or
`$work/terraform-provider-unifi`, run the tests:

```sh
(cd "$work/go-unifi" && go test ./unifi/...)
cd "$work/terraform-provider-unifi"
go vet ./... && go list ./... | grep -v /internal/provider/acctest | xargs go test
```

and write the series back (for the provider, leave out the generated
`build: use patched go-unifi` commit, the last one):

```sh
rm -f patches/go-unifi/*.patch
git -C "$work/go-unifi" format-patch --zero-commit --no-signature \
  --base=v1.9.3 -o "$PWD/patches/go-unifi" v1.9.3
```

To build locally, run GoReleaser in `$work/terraform-provider-unifi` after
tagging the patched commit, for example
`git tag v1.1.0-dkn.0 && goreleaser release --clean --config <this repo>/.goreleaser.yml`.

## License

The provider and go-unifi are licensed under the
[Mozilla Public License 2.0](LICENSE), and so are these patches. The source of
release `vX.Y.Z-dkn.N` is the upstream tags named in its release notes with the
patches in this repository at the tag `vX.Y.Z-dkn.N` applied in order.
