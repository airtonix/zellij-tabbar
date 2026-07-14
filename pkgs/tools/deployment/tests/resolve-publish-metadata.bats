#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../../.." && pwd)"
  SCRIPT="${REPO_ROOT}/pkgs/tools/deployment/resolve-publish-metadata"
  TEST_ROOT="$(mktemp -d)"
  REPO="${TEST_ROOT}/repo"
  mkdir -p "${REPO}/packages/node" "${REPO}/crates/rust/src" "${REPO}/packages/private" "${REPO}/packages/bad" "${TEST_ROOT}/bin"

  echo '{"name":"node","version":"1.2.3"}' >"${REPO}/packages/node/package.json"
  echo '{"name":"private","version":"4.5.6"}' >"${REPO}/packages/private/package.json"
  echo '{"name":"bad","version":"broken"}' >"${REPO}/packages/bad/package.json"
  cat >"${REPO}/crates/rust/Cargo.toml" <<'EOF'
[package]
name = "rust"
version = "2.3.4"
edition = "2021"
EOF
  echo '' >"${REPO}/crates/rust/src/lib.rs"

  cat >"${TEST_ROOT}/bin/moon" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
{"projects":[
  {"id":"node","source":"packages/node","tasks":{"publish":{}}},
  {"id":"rust","source":"crates/rust","tasks":{"publish":{}}},
  {"id":"private","source":"packages/private","tasks":{"test":{}}},
  {"id":"bad","source":"packages/bad","tasks":{"publish":{}}}
]}
JSON
EOF
  chmod +x "${TEST_ROOT}/bin/moon"

  git init -q -b main "${REPO}"
  git -C "${REPO}" config user.email test@example.com
  git -C "${REPO}" config user.name Test
  git -C "${REPO}" add .
  git -C "${REPO}" commit -qm root
}

teardown() {
  rm -rf "${TEST_ROOT}"
}

resolve() {
  bash -c "cd '${REPO}' && PATH='${TEST_ROOT}/bin:${PATH}' '${SCRIPT}' $*"
}

@test "latest resolves Node and Cargo source versions with component tags" {
  run resolve node latest main 1
  [ "${status}" -eq 0 ]
  [ "$(jq -r .version <<<"${output}")" = 1.2.3 ]
  [ "$(jq -r .release_tag <<<"${output}")" = node-v1.2.3 ]

  run resolve rust latest main 1
  [ "${status}" -eq 0 ]
  [ "$(jq -r .version <<<"${output}")" = 2.3.4 ]
  [ "$(jq -r .release_tag <<<"${output}")" = rust-v2.3.4 ]
}

@test "main next bumps minor from latest stable component tag and uses run attempt" {
  git -C "${REPO}" tag node-v1.2.3
  echo change >>"${REPO}/change"
  git -C "${REPO}" add change
  git -C "${REPO}" commit -qm change
  git -C "${REPO}" tag node-v9.0.0-next.99.1

  run resolve node next main 2
  [ "${status}" -eq 0 ]
  [ "$(jq -r .stable_tag <<<"${output}")" = node-v1.2.3 ]
  [ "$(jq -r .commit_distance <<<"${output}")" = 1 ]
  [ "$(jq -r .version <<<"${output}")" = 1.3.0-next.1.2 ]
}

@test "release next bumps patch" {
  git -C "${REPO}" tag node-v1.2.3
  git -C "${REPO}" checkout -qb release/1.2
  echo hotfix >>"${REPO}/change"
  git -C "${REPO}" add change
  git -C "${REPO}" commit -qm hotfix

  run resolve node next release/1.2 1
  [ "${status}" -eq 0 ]
  [ "$(jq -r .version <<<"${output}")" = 1.2.4-next.1.1 ]
}

@test "missing component tag falls back to source-path historical tag" {
  git -C "${REPO}" tag packages/node-v1.2.3
  echo source-fallback >>"${REPO}/change"
  git -C "${REPO}" add change
  git -C "${REPO}" commit -qm source-fallback

  run resolve node next main 1
  [ "${status}" -eq 0 ]
  [ "$(jq -r .stable_tag <<<"${output}")" = packages/node-v1.2.3 ]
}

@test "no stable tag uses first-parent history from repository root" {
  run resolve node next main 1
  [ "${status}" -eq 0 ]
  [ "$(jq -r .stable_tag <<<"${output}")" = "" ]
  [ "$(jq -r .commit_distance <<<"${output}")" = 1 ]
  [ "$(jq -r .version <<<"${output}")" = 1.3.0-next.1.1 ]
}

@test "unknown, non-publishable, malformed, and unsupported branch inputs fail" {
  run resolve missing latest main 1
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Unknown Moon target"* ]]

  run resolve private latest main 1
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"not publishable"* ]]

  run resolve bad latest main 1
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Malformed semantic version"* ]]

  echo '{"name":"bad","version":"1.2.3-rc.1"}' >"${REPO}/packages/bad/package.json"
  run resolve bad latest main 1
  [ "${status}" -ne 0 ]

  echo '{"name":"bad","version":"1.02.3"}' >"${REPO}/packages/bad/package.json"
  run resolve bad next main 1
  [ "${status}" -ne 0 ]

  run resolve node next feature/test 1
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Unsupported source branch"* ]]
}
