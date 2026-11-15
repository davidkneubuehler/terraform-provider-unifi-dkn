#!/usr/bin/env bash
# Check out the upstream provider at the tag in UPSTREAM_VERSION and the
# go-unifi release it requires, and apply patches/ on top of both.
#
# Usage: scripts/prepare-source.sh DEST
#
#   DEST  directory to create; it must not exist yet. It receives
#         DEST/terraform-provider-unifi and DEST/go-unifi.
#
# patches/terraform-provider-unifi/*.patch apply to the provider and
# patches/go-unifi/*.patch to go-unifi, each with `git am -3`. When go-unifi
# has patches, the provider's go.mod gets a `replace` to ../go-unifi, committed
# so that the provider checkout is clean for GoReleaser.
# On a patch that does not apply, the script names it, lists the conflicts
# and exits with status 1, leaving the checkout in the failed `git am` state.
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 DEST" >&2
  exit 2
fi

dest=$1
root=$(cd "$(dirname "$0")/.." && pwd)
version=$(tr -d '[:space:]' < "$root/UPSTREAM_VERSION")
provider_url=${PROVIDER_REPOSITORY_URL:-https://github.com/filipowm/terraform-provider-unifi.git}
go_unifi_url=${GO_UNIFI_REPOSITORY_URL:-https://github.com/filipowm/go-unifi.git}
go_unifi_module=github.com/filipowm/go-unifi

if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "invalid upstream version in UPSTREAM_VERSION: $version" >&2
  exit 2
fi
if [ -e "$dest" ]; then
  echo "$dest already exists" >&2
  exit 2
fi
mkdir -p "$dest"
dest=$(cd "$dest" && pwd)

# The identity only labels the local commits; nothing from these checkouts is pushed.
git_local() {
  git -c user.name=terraform-provider-unifi-dkn \
    -c user.email=terraform-provider-unifi-dkn@users.noreply.github.com "$@"
}

# apply_series NAME DIR VERSION: apply patches/NAME/*.patch to the checkout DIR.
apply_series() {
  local name=$1 dir=$2 tag=$3
  local series base next applied patch subject
  shopt -s nullglob
  series=("$root/patches/$name"/*.patch)
  shopt -u nullglob
  if [ ${#series[@]} -eq 0 ]; then
    return 0
  fi

  # `git am -3` needs the blobs the patches were made against to fall back to
  # a three-way merge. The series records its upstream base (format-patch --base).
  base=$(sed -n 's/^base-commit: //p' "${series[@]}" | head -n 1)
  if [ -n "$base" ] && ! git -C "$dir" cat-file -e "$base^{commit}" 2>/dev/null; then
    git -C "$dir" fetch --quiet --depth 1 origin "$base"
  fi

  if ! git_local -C "$dir" am --quiet -3 "${series[@]}"; then
    # Read the stopped session's state from files: a failing diagnostic must
    # not end the script (set -e) before the report below is complete.
    next=$(cat "$(git -C "$dir" rev-parse --path-format=absolute --git-path rebase-apply/next 2>/dev/null)" 2>/dev/null || echo 1)
    applied=$((next - 1))
    patch=${series[$applied]}
    subject=$(sed -n 's/^Subject: \(\[PATCH[^]]*\] \)\{0,1\}//p' "$patch" | head -n 1 || true)
    echo "::error title=Patch failed::$name/${patch##*/} ($subject) does not apply to $name $tag"
    echo "Applied cleanly: $applied of ${#series[@]}"
    echo "Failed patch: $name/${patch##*/}"
    echo "Conflicts:"
    git -C "$dir" diff --name-only --diff-filter=U 2>/dev/null | sed 's/^/  /' || true
    exit 1
  fi
  for patch in "${series[@]}"; do
    echo "Applied $name/${patch##*/}"
  done
}

clone() {
  git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$2" "$1" "$3"
}

provider=$dest/terraform-provider-unifi
clone "$provider_url" "$version" "$provider"
echo "terraform-provider-unifi $version: $(git -C "$provider" rev-parse HEAD)"
apply_series terraform-provider-unifi "$provider" "$version"

# Take the go-unifi version from the (patched) provider go.mod.
go_unifi_version=$(awk -v m="$go_unifi_module" '$1 == m || ($1 == "require" && $2 == m) { print $NF; exit }' "$provider/go.mod")
if [[ ! "$go_unifi_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "cannot read the $go_unifi_module version from go.mod: '$go_unifi_version'" >&2
  exit 1
fi

shopt -s nullglob
go_unifi_patches=("$root/patches/go-unifi"/*.patch)
shopt -u nullglob
if [ ${#go_unifi_patches[@]} -gt 0 ]; then
  go_unifi=$dest/go-unifi
  clone "$go_unifi_url" "$go_unifi_version" "$go_unifi"
  echo "go-unifi $go_unifi_version: $(git -C "$go_unifi" rev-parse HEAD)"
  apply_series go-unifi "$go_unifi" "$go_unifi_version"

  (cd "$provider" && go mod edit -replace "$go_unifi_module=../go-unifi")
  git_local -C "$provider" commit --quiet -m "build: use patched go-unifi $go_unifi_version" go.mod
  echo "go.mod: replace $go_unifi_module => ../go-unifi"
fi
