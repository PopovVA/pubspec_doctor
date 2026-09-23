#!/usr/bin/env bash
#
# Fails the build when something that belongs to one developer's machine or
# account reaches the repository: a signing team, a home directory path, a
# personal address, or a credential.
#
# Xcode writes DEVELOPMENT_TEAM into an example project the first time anyone
# builds it on a device, which is how a team id once shipped to pub.dev inside
# this package. This check is here so that cannot happen again quietly.
#
# Files whose content is deliberately fake, such as fixtures for a security
# scanner, go in .github/leak-scan-allow.txt, one path per line.

set -uo pipefail

self="${BASH_SOURCE[0]#./}"
allow_file=".github/leak-scan-allow.txt"

# Pathspecs excluded from every search: this script, and anything allowlisted.
excludes=(":!$self")
if [ -f "$allow_file" ]; then
  excludes+=(":!$allow_file")
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in '' | '#'*) continue ;; esac
    excludes+=(":!$line")
  done < "$allow_file"
fi

failed=0

# Reports every tracked file matching a regex, ignoring the exclusions.
# An optional third argument drops matching lines from the result, which is
# how documented placeholders stay allowed.
scan() {
  local label="$1" regex="$2" ignore="${3:-}" hits
  hits=$(git grep -nEI -e "$regex" -- . "${excludes[@]}" 2>/dev/null)
  if [ -n "$hits" ] && [ -n "$ignore" ]; then
    hits=$(printf '%s\n' "$hits" | grep -Ev -- "$ignore")
  fi
  if [ -n "$hits" ]; then
    printf '\n%s\n' "$label"
    printf '%s\n' "$hits" | sed 's/^/  /'
    failed=1
  fi
}

# Names that should never be tracked, whatever they contain.
forbidden_names() {
  local hits
  hits=$(git ls-files -- '*.p8' '*.p12' '*.pem' '*.keystore' '*.jks' \
    '*.mobileprovision' '.env' '**/.env' '*.env.local' "${excludes[@]}" 2>/dev/null)
  if [ -n "$hits" ]; then
    printf '\nCredential files must not be committed:\n'
    printf '%s\n' "$hits" | sed 's/^/  /'
    failed=1
  fi
}

forbidden_names

scan 'An Apple signing team belongs to whoever builds, not to the repository:' \
  'DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*[A-Z0-9]{8,}'

# Placeholders such as /Users/you or /Users/username are fine in docs.
scan 'A path from someone'"'"'s machine:' \
  '/(Users|home)/[A-Za-z0-9._-]+/' \
  '/(Users|home)/(you|your-name|username|user|me|runner|<[^>]+>|\$)'

scan 'A personal address:' \
  '[A-Za-z0-9._%+-]+@(gmail|googlemail|icloud|me|yahoo|outlook|hotmail|proton|protonmail)\.(com|me)'

scan 'A credential:' \
  '(gh[pousr]_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9]{32,}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----[^-]+)'

if [ "$failed" -ne 0 ]; then
  printf '\nIf a match is deliberate, add its path to %s\n' "$allow_file"
  exit 1
fi

printf 'No leaked identifiers or credentials.\n'
