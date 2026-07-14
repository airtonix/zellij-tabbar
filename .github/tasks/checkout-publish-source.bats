#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  SCRIPT="${REPO_ROOT}/.github/tasks/checkout-publish-source"
  TEST_ROOT="$(mktemp -d)"
  remote="${TEST_ROOT}/remote.git"
  source_repo="${TEST_ROOT}/source"
  checkout_repo="${TEST_ROOT}/checkout"

  git init -q --bare "${remote}"
  git init -q -b main "${source_repo}"
  git -C "${source_repo}" config user.email test@example.com
  git -C "${source_repo}" config user.name Test
  echo root >"${source_repo}/file"
  git -C "${source_repo}" add file
  git -C "${source_repo}" commit -qm root
  git -C "${source_repo}" remote add origin "${remote}"
  git -C "${source_repo}" push -q -u origin main
  valid_sha="$(git -C "${source_repo}" rev-parse HEAD)"

  git clone -q "${remote}" "${checkout_repo}"
}

teardown() {
  rm -rf "${TEST_ROOT}"
}

@test "reachable source SHA is checked out exactly" {
  run bash -c "cd '${checkout_repo}' && '${SCRIPT}' '${valid_sha}' main"
  [ "${status}" -eq 0 ]
  [ "$(git -C "${checkout_repo}" rev-parse HEAD)" = "${valid_sha}" ]
}

@test "source SHA outside claimed branch is rejected" {
  git -C "${source_repo}" checkout -q --orphan unrelated
  git -C "${source_repo}" rm -q -f file
  echo unrelated >"${source_repo}/other"
  git -C "${source_repo}" add other
  git -C "${source_repo}" commit -qm unrelated
  unrelated_sha="$(git -C "${source_repo}" rev-parse HEAD)"
  git -C "${checkout_repo}" fetch -q "${source_repo}" "${unrelated_sha}"

  run bash -c "cd '${checkout_repo}' && '${SCRIPT}' '${unrelated_sha}' main"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"is not reachable"* ]]
}
