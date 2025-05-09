#!/bin/bash

# Usage: ./purge_tagged_secrets.sh <keyvault-name> <tag1> <tag2> ...

KEYVAULT=$1
shift
TAGS=("$@")

if [[ -z "$KEYVAULT" || ${#TAGS[@]} -eq 0 ]]; then
  echo "Usage: $0 <keyvault-name> <tag1> <tag2> ..."
  exit 1
fi

echo "Purging secrets from Key Vault: $KEYVAULT"
echo "Matching tags: ${TAGS[*]}"

for TAG in "${TAGS[@]}"; do
  echo "Searching for secrets with tag: $TAG"

  secret_names=$(az keyvault secret list --vault-name "$KEYVAULT" --query "[?starts_with(name, '$TAG')].name" -o tsv)

  for secret_name in $secret_names; do
    echo "Deleting secret: $secret_name"
    az keyvault secret delete --vault-name "$KEYVAULT" --name "$secret_name" >/dev/null

    echo "Purging secret: $secret_name"
    for attempt in {1..5}; do
      az keyvault secret purge --vault-name "$KEYVAULT" --name "$secret_name" >/dev/null && break

      echo "Purge attempt $attempt failed (likely still deleting). Retrying in 10s..."
      sleep 10
    done

    # Check again in case all attempts failed
    az keyvault secret show-deleted --vault-name "$KEYVAULT" --name "$secret_name" &>/dev/null
    if [[ $? -eq 0 ]]; then
      echo "Still unable to purge $secret_name after retries."
    else
      echo "Purged: $secret_name"
    fi
  done
done

echo "Done purging secrets."
