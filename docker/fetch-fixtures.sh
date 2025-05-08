#!/bin/bash

set -euo pipefail

VAULT_NAME=$1
COMPOSE_FILE="docker-compose.yml"

if [[ -z "$VAULT_NAME" ]]; then
  echo "Usage: $0 <keyvault-name>"
  exit 1
fi

# Extract service names from docker-compose.yml
TAGS=($(yq e '.services | keys | .[]' "$COMPOSE_FILE"))
echo "Extracted tags from docker-compose: ${TAGS[*]}"
echo "Downloading secrets from Key Vault: $VAULT_NAME"

for TAG in "${TAGS[@]}"; do
  echo "Checking secrets for tag: $TAG"

  SECRET_NAMES=$(az keyvault secret list --vault-name "$VAULT_NAME" --query "[?starts_with(name, '$TAG--')].name" -o tsv)

  if [[ -z "$SECRET_NAMES" ]]; then
    echo "No secrets found for tag: $TAG"
    continue
  fi

  while IFS= read -r SECRET_NAME; do
    ENCODED_PATH=${SECRET_NAME#"$TAG--"}

    # Base64 may need padding, so fix length to a multiple of 4
    PADDED_PATH="$ENCODED_PATH"
    while (( ${#PADDED_PATH} % 4 != 0 )); do
      PADDED_PATH+="="
    done

    # Decode
    if ! REL_PATH=$(echo "$PADDED_PATH" | base64 --decode 2>/dev/null); then
      echo "Could not decode secret name: $SECRET_NAME"
      continue
    fi

    FULL_PATH="$TAG/$REL_PATH"
    DIR_PATH=$(dirname "$FULL_PATH")
    mkdir -p "$DIR_PATH"

    SECRET_VALUE=$(az keyvault secret show --vault-name "$VAULT_NAME" --name "$SECRET_NAME" --query value -o tsv)
    #echo -n "$SECRET_VALUE" | sed -e '$a\' > "$FULL_PATH"
    printf '%s\n' "$SECRET_VALUE" > "$FULL_PATH"

    echo "Saved $SECRET_NAME → $FULL_PATH"
  done <<< "$SECRET_NAMES"
done

echo "Done downloading secrets."
