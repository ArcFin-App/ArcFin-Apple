#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Tags tonight's build $TAG at $SHA, signed with arcfin-bot's CI key, and pushes it as the bot.
#
# The runner works in the maintainer's own login, whose git config signs with their key, so
# every signing setting is given here, the key goes in a keyring of its own, and the tag is
# only pushed once its signature is checked to be the bot's. The keyring lives in a short
# /tmp path: gpg-agent's socket path has a length limit the runner's temp folder goes over.
set -euo pipefail

: "${TOKEN:?RELEASE_TOKEN isn't set}" "${BOT_GPG_KEY:?ARCFIN_BOT_GPG_KEY isn't set}"
remote="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}.git"
auth="Authorization: Basic $(printf 'arcfin-bot:%s' "$TOKEN" | base64 | tr -d '\n')"

if git -c http.extraHeader="$auth" ls-remote --exit-code --tags "$remote" "refs/tags/$TAG" > /dev/null; then
  echo "$TAG is already there"
  exit 0
fi

export GNUPGHOME
GNUPGHOME=$(mktemp -d /tmp/arcfin-gpg.XXXXXX)
trap 'gpgconf --kill gpg-agent 2>/dev/null; rm -rf "$GNUPGHOME"' EXIT
printf '%s' "$BOT_GPG_KEY" | base64 --decode | gpg --batch --quiet --import
key=$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr/ {print $10; exit}')

git -c user.name="Arcfin Bot" -c user.email=arcfin-bot@psmattas.com \
  -c gpg.format=openpgp -c gpg.program=gpg -c gpg.openpgp.program=gpg -c user.signingkey="$key" \
  tag -s -f "$TAG" "$SHA" -m "Arcfin $VERSION ($BUILD) for $UPLOADED"

signer=$(git -c gpg.program=gpg verify-tag --raw "$TAG" 2>&1 | awk '/VALIDSIG/ {print $3; exit}')
if [ "$signer" != "$key" ]; then
  echo "::error::$TAG wasn't signed with arcfin-bot's key (${signer:-no valid signature})"
  exit 1
fi

git -c http.extraHeader="$auth" push "$remote" "refs/tags/$TAG"
echo "Tagged $TAG, signed by arcfin-bot (${key: -16})"
