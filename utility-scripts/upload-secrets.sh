#!/bin/bash

VAULT_NAME=$1
COMPOSE_FILE="docker-compose.yml"

if [[ -z "$VAULT_NAME" ]]; then
  echo "Usage: $0 <keyvault-name>"
  exit 1
fi

# Extract service names as tags
TAGS=($(yq e '.services | keys | .[]' "$COMPOSE_FILE"))

echo "Uploading secrets to Key Vault: $VAULT_NAME"
echo "Processing tags: ${TAGS[*]}"

for TAG in "${TAGS[@]}"; do
  FIXTURE_DIR="${TAG}/fixture"
  if [[ ! -d "$FIXTURE_DIR" ]]; then
    echo "Directory not found: $FIXTURE_DIR"
    continue
  fi

  echo "Processing tag: $TAG in $FIXTURE_DIR"
  while IFS= read -r -d '' FILE; do
    BASENAME=$(basename "$FILE")
    [[ "$BASENAME" == .* ]] && continue  # Skip hidden files like .gitignore

    REL_PATH=${FILE#${TAG}/}
    ENCODED=$(echo -n "$REL_PATH" | base64 | tr '+/' '-_' | tr -d '=')
    SECRET_NAME="${TAG}--${ENCODED}"

    echo "Creating secret: $SECRET_NAME"
    VALUE=$(<"$FILE")

    if ! az keyvault secret set --vault-name "$VAULT_NAME" --name "$SECRET_NAME" --value "$VALUE" &>/dev/null; then
      echo "Initial upload failed for $SECRET_NAME"
      if az keyvault secret show-deleted --vault-name "$VAULT_NAME" --name "$SECRET_NAME" &>/dev/null; then
        echo "Purging deleted secret: $SECRET_NAME"
        az keyvault secret purge --vault-name "$VAULT_NAME" --name "$SECRET_NAME" >/dev/null
        echo "Waiting for purge to complete..."
        sleep 10
        echo "Retrying upload for $SECRET_NAME"
        if ! az keyvault secret set --vault-name "$VAULT_NAME" --name "$SECRET_NAME" --value "$VALUE" &>/dev/null; then
          echo "Retry failed for $SECRET_NAME"
        else
          echo "Upload after purge: $SECRET_NAME"
        fi
      else
        echo "Upload failed and no deleted secret found: $SECRET_NAME"
      fi
    else
      echo "Uploaded: $SECRET_NAME"
    fi
  done < <(find "$FIXTURE_DIR" -type f -print0)
done

echo "Done uploading secrets."
