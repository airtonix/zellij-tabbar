#!/usr/bin/env bash

set -euo pipefail

normal_config="${1:-release-please-config--release.json}"
hotfix_config="${2:-release-please-config--hotfix.json}"
manifest_file="${3:-.release-please-manifest.json}"

for command in moon jq; do
  command -v "${command}" >/dev/null || { echo "Missing required command: ${command}" >&2; exit 1; }
done
for file in "${normal_config}" "${hotfix_config}" "${manifest_file}"; do
  [[ -f "${file}" ]] || { echo "Missing Release Please file: ${file}" >&2; exit 1; }
  jq -e . "${file}" >/dev/null
 done

read_cargo_version() {
  local source="$1"
  local source_abs metadata
  source_abs="$(realpath "${source}")"
  metadata="$(cargo metadata --no-deps --format-version 1 --manifest-path "${source}/Cargo.toml")"
  jq -r --arg source "${source_abs}" '
    first(
      .packages[]
      | select((.manifest_path | sub("/Cargo.toml$"; "")) == $source)
      | .version
    ) // empty
  ' <<<"${metadata}"
}

resolve_version_source() {
  local source="$1"
  local id="$2"
  local version_source

  if [[ -f "${source}/package.json" ]]; then
    version_source=package.json
  elif [[ -f "${source}/Cargo.toml" ]]; then
    version_source=Cargo.toml
  else
    version_source=unsupported
  fi

  # Version-source extension boundary: add new package metadata formats as explicit cases.
  case "${version_source}" in
    package.json)
      release_type=node
      version="$(jq -r '.version // empty' "${source}/package.json")"
      ;;
    Cargo.toml)
      command -v cargo >/dev/null || { echo "Missing required command: cargo" >&2; exit 1; }
      release_type=rust
      version="$(read_cargo_version "${source}")"
      ;;
    *)
      echo "Unsupported version source for publishable Moon project '${id}' at '${source}'" >&2
      exit 1
      ;;
  esac
}

projects_json="$(moon query projects)"
entries='[]'

while IFS= read -r project; do
  id="$(jq -r '.id' <<<"${project}")"
  source="$(jq -r '.source' <<<"${project}")"

  case "${source}" in
    ""|null)
      echo "Publishable Moon project '${id}' has no source" >&2
      exit 1
      ;;
  esac

  resolve_version_source "${source}" "${id}"

  if [[ ! "${version}" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "Malformed semantic version '${version}' for Moon project '${id}'" >&2
    exit 1
  fi

  entry="$(jq -n \
    --arg source "${source}" \
    --arg component "${id}" \
    --arg release_type "${release_type}" \
    --arg version "${version}" \
    '{source: $source, component: $component, release_type: $release_type, version: $version}')"
  entries="$(jq -c --argjson entry "${entry}" '. + [$entry] | sort_by(.source)' <<<"${entries}")"
done < <(jq -c '.projects[] | select((.tasks // {}) | has("publish"))' <<<"${projects_json}")

[[ "$(jq 'length' <<<"${entries}")" -gt 0 ]] || { echo "No publishable Moon projects found" >&2; exit 1; }

sync_config() {
  local file="$1"
  local old_packages packages temp
  old_packages="$(jq '.packages // {}' "${file}")"
  packages="$(jq -n --argjson entries "${entries}" --argjson old "${old_packages}" '
    reduce $entries[] as $entry ({};
      .[$entry.source] = (
        ($old[$entry.source] // {})
        + {"component": $entry.component, "release-type": $entry.release_type}
      )
    )
  ')"
  temp="$(mktemp "${file}.XXXXXX")"
  jq --argjson packages "${packages}" '.packages = $packages' "${file}" >"${temp}"
  mv "${temp}" "${file}"
}

sync_config "${normal_config}"
sync_config "${hotfix_config}"

old_manifest="$(cat "${manifest_file}")"
new_manifest="$(jq -n --argjson entries "${entries}" --argjson old "${old_manifest}" '
  reduce $entries[] as $entry ({};
    .[$entry.source] = ($old[$entry.source] // $entry.version)
  )
')"
temp="$(mktemp "${manifest_file}.XXXXXX")"
printf '%s\n' "${new_manifest}" >"${temp}"
mv "${temp}" "${manifest_file}"
