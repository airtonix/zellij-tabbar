#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  SCRIPT="${REPO_ROOT}/.github/tasks/ensure-publish-release"
  TEST_ROOT="$(mktemp -d)"
  mkdir -p "${TEST_ROOT}/bin"
  STATE_FILE="${TEST_ROOT}/release"

  cat >"${TEST_ROOT}/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1 $2" == 'release view' ]]; then
  [[ -f "${MOCK_STATE_FILE}" ]] || exit 1
  jq -n \
    --argjson draft "${MOCK_DRAFT:-false}" \
    --argjson prerelease "${MOCK_PRERELEASE:-true}" \
    '{isDraft: $draft, isPrerelease: $prerelease}'
elif [[ "$1 $2" == 'release create' ]]; then
  touch "${MOCK_STATE_FILE}"
  [[ "${MOCK_CREATE_RACE:-false}" == true ]] && exit 1
else
  exit 2
fi
EOF

  cat >"${TEST_ROOT}/bin/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  check-ref-format|fetch) exit 0 ;;
  rev-list) printf '%s\n' "${MOCK_TAG_SHA}" ;;
  *) exit 2 ;;
esac
EOF
  chmod +x "${TEST_ROOT}/bin/gh" "${TEST_ROOT}/bin/git"
}

teardown() {
  rm -rf "${TEST_ROOT}"
}

ensure_release() {
  env PATH="${TEST_ROOT}/bin:${PATH}" \
    MOCK_STATE_FILE="${STATE_FILE}" \
    MOCK_DRAFT="${MOCK_DRAFT:-false}" \
    MOCK_PRERELEASE="${MOCK_PRERELEASE:-true}" \
    MOCK_CREATE_RACE="${MOCK_CREATE_RACE:-false}" \
    MOCK_TAG_SHA="${MOCK_TAG_SHA:-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}" \
    "${SCRIPT}" "$@"
}

@test "latest rejects prerelease and next rejects stable release" {
  touch "${STATE_FILE}"
  MOCK_PRERELEASE=true run ensure_release latest component-v1.0.0 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"wrong prerelease state"* ]]

  MOCK_PRERELEASE=false run ensure_release next component-v1.0.0 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"wrong prerelease state"* ]]
}

@test "next tolerates concurrent creation and verifies exact tag target" {
  MOCK_CREATE_RACE=true run ensure_release next component-v1.0.0 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  [ "${status}" -eq 0 ]

  MOCK_TAG_SHA=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb run ensure_release next component-v1.0.0 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"expected 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'"* ]]
}

@test "draft release is rejected" {
  touch "${STATE_FILE}"
  MOCK_DRAFT=true run ensure_release next component-v1.0.0 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"is a draft"* ]]
}
