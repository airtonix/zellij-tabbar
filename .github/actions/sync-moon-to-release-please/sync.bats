#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  SCRIPT="${REPO_ROOT}/.github/actions/sync-moon-to-release-please/action.sh"
  TEST_ROOT="$(mktemp -d)"
  mkdir -p "${TEST_ROOT}/bin"

  for config in release-please-config--release.json release-please-config--hotfix.json; do
    cat >"${TEST_ROOT}/${config}" <<'JSON'
{"separate-pull-requests":false,"packages":{"stale":{"release-type":"node"}}}
JSON
  done
  echo '{}' >"${TEST_ROOT}/.release-please-manifest.json"
}

teardown() {
  rm -rf "${TEST_ROOT}"
}

write_moon() {
  cat >"${TEST_ROOT}/bin/moon" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
{"projects":[
  {"id":"node-app","source":"apps/node","tasks":{"publish":{}}},
  {"id":"rust-lib","source":"crates/rust-lib","tasks":{"publish":{}}},
  {"id":"private-tool","source":"tools/private","tasks":{"test":{}}}
]}
JSON
EOF
  chmod +x "${TEST_ROOT}/bin/moon"
}

@test "sync discovers Node and Cargo projects, preserves versions, and aligns configs" {
  write_moon
  mkdir -p "${TEST_ROOT}/apps/node" "${TEST_ROOT}/crates/rust-lib/src" "${TEST_ROOT}/tools/private"
  echo '{"name":"node-app","version":"1.2.3"}' >"${TEST_ROOT}/apps/node/package.json"
  cat >"${TEST_ROOT}/crates/rust-lib/Cargo.toml" <<'EOF'
[package]
name = "rust-lib"
version = "2.3.4"
edition = "2021"
EOF
  echo '' >"${TEST_ROOT}/crates/rust-lib/src/lib.rs"
  echo '{"apps/node":"9.9.9"}' >"${TEST_ROOT}/.release-please-manifest.json"

  run bash -c "cd '${TEST_ROOT}' && PATH='${TEST_ROOT}/bin:${PATH}' '${SCRIPT}'"
  [ "${status}" -eq 0 ]

  [ "$(jq -r '."apps/node"' "${TEST_ROOT}/.release-please-manifest.json")" = 9.9.9 ]
  [ "$(jq -r '."crates/rust-lib"' "${TEST_ROOT}/.release-please-manifest.json")" = 2.3.4 ]
  [ "$(jq -r '.packages."apps/node".component' "${TEST_ROOT}/release-please-config--release.json")" = node-app ]
  [ "$(jq -r '.packages."apps/node"."release-type"' "${TEST_ROOT}/release-please-config--release.json")" = node ]
  [ "$(jq -r '.packages."crates/rust-lib".component' "${TEST_ROOT}/release-please-config--release.json")" = rust-lib ]
  [ "$(jq -r '.packages."crates/rust-lib"."release-type"' "${TEST_ROOT}/release-please-config--release.json")" = rust ]
  [ "$(jq -c '.packages' "${TEST_ROOT}/release-please-config--release.json")" = "$(jq -c '.packages' "${TEST_ROOT}/release-please-config--hotfix.json")" ]
  ! jq -e '.packages.stale or .packages."tools/private"' "${TEST_ROOT}/release-please-config--release.json"
}

@test "sync rejects prerelease and leading-zero source versions" {
  cat >"${TEST_ROOT}/bin/moon" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"projects":[{"id":"node","source":"packages/node","tasks":{"publish":{}}}]}'
EOF
  chmod +x "${TEST_ROOT}/bin/moon"
  mkdir -p "${TEST_ROOT}/packages/node"

  echo '{"name":"node","version":"1.2.3-rc.1"}' >"${TEST_ROOT}/packages/node/package.json"
  run bash -c "cd '${TEST_ROOT}' && PATH='${TEST_ROOT}/bin:${PATH}' '${SCRIPT}'"
  [ "${status}" -ne 0 ]

  echo '{"name":"node","version":"1.02.3"}' >"${TEST_ROOT}/packages/node/package.json"
  run bash -c "cd '${TEST_ROOT}' && PATH='${TEST_ROOT}/bin:${PATH}' '${SCRIPT}'"
  [ "${status}" -ne 0 ]
}

@test "sync fails for publishable project without supported version source" {
  cat >"${TEST_ROOT}/bin/moon" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '{"projects":[{"id":"unknown","source":"packages/unknown","tasks":{"publish":{}}}]}'
EOF
  chmod +x "${TEST_ROOT}/bin/moon"
  mkdir -p "${TEST_ROOT}/packages/unknown"

  run bash -c "cd '${TEST_ROOT}' && PATH='${TEST_ROOT}/bin:${PATH}' '${SCRIPT}'"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Unsupported version source"* ]]
}
