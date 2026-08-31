#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <previous-ref> <release-ref>" >&2
  exit 1
fi

previous_ref=$1
release_ref=$2

git rev-parse --verify "${previous_ref}^{commit}" >/dev/null
git rev-parse --verify "${release_ref}^{commit}" >/dev/null

features=()
fixes=()
improvements=()
dependencies=()
other_changes=()
conventional_commit_pattern='^([a-z]+)(\(([^)]+)\))?(!)?:[[:space:]]+(.+)$'

while IFS=$'\t' read -r sha subject; do
  [[ -n $subject ]] || continue

  type=
  scope=
  description=$subject

  if [[ $subject =~ $conventional_commit_pattern ]]; then
    type=${BASH_REMATCH[1]}
    scope=${BASH_REMATCH[3]}
    description=${BASH_REMATCH[5]}
  fi

  if [[ -n $scope ]]; then
    entry="- **${scope}:** ${description} (${sha})"
  else
    entry="- ${description} (${sha})"
  fi

  case "${type}:${scope}" in
    feat:*) features+=("$entry") ;;
    fix:*) fixes+=("$entry") ;;
    perf:* | refactor:*) improvements+=("$entry") ;;
    chore:deps | chore:dependencies | build:deps | build:dependencies) dependencies+=("$entry") ;;
    *) other_changes+=("$entry") ;;
  esac
done < <(git log --no-merges --reverse --pretty=tformat:'%h%x09%s' "${previous_ref}..${release_ref}")

print_section() {
  local title=$1
  shift

  [[ $# -gt 0 ]] || return 0

  printf '## %s\n\n' "$title"
  printf '%s\n' "$@"
  printf '\n'
}

print_section "Features" "${features[@]}"
print_section "Bug fixes" "${fixes[@]}"
print_section "Improvements" "${improvements[@]}"
print_section "Other changes" "${other_changes[@]}"

if [[ ${#dependencies[@]} -gt 0 ]]; then
  dependency_label=updates
  [[ ${#dependencies[@]} -ne 1 ]] || dependency_label=update
  printf '<details>\n<summary>Dependencies (%d %s)</summary>\n\n' "${#dependencies[@]}" "$dependency_label"
  printf '%s\n' "${dependencies[@]}"
  printf '\n</details>\n\n'
fi

if [[ -n ${RELEASE_IMAGE:-} ]]; then
  printf '## Container image\n\n'
  printf '%s\n' "\`docker pull ${RELEASE_IMAGE}\`"
  if [[ -n ${RELEASE_DIGEST:-} ]]; then
    printf '\n%s\n' "Digest: \`${RELEASE_DIGEST}\`"
  fi
  printf '\n'
fi

repository=${GITHUB_REPOSITORY:-}
if [[ -z $repository ]]; then
  repository=$(git remote get-url origin | sed -E 's#^(git@github.com:|https://github.com/)##; s#\.git$##')
fi

printf '**Full changelog:** https://github.com/%s/compare/%s...%s\n' "$repository" "$previous_ref" "$release_ref"
