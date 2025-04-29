#!/usr/bin/env bash

echo "Fetching manifests to delete..."
HUB_TOKEN=$(curl -s -H "Content-Type: application/json" -X POST \
  -d "{\"username\": \"${HUB_USERNAME}\", \"password\": \"${HUB_PASSWORD}\"}" \
  https://hub.docker.com/v2/users/login/ | jq -r .token)
[ -z "$HUB_TOKEN" ] && { echo "❌ Authentication failed"; exit 1; }

MANIFESTS=$(curl -s -H "Authorization: JWT $HUB_TOKEN" \
  "https://hub.docker.com/v2/repositories/${IMAGE_NAME}/tags/?page_size=${MAX_DELETIONS}&ordering=last_updated" \
  | jq -r '.results[] | select(.images != null) | .images[].digest' \
  | sort | uniq | head -n $MAX_DELETIONS)

DELETED_MANIFESTS=0
for SHA in $MANIFESTS; do
  echo "Processing manifest ${SHA:0:12}..."
  
  # 1. Extract clean SHA256 (remove 'sha256:' prefix if present)
  CLEAN_SHA="${SHA#sha256:}"
  
  # 2. Get the manifest reference first (required for Docker Hub)
  echo "Getting manifest reference..."
  MANIFEST_REF=$(curl -s -H "Authorization: JWT $HUB_TOKEN" \
    -H "Accept: application/json" \
    "https://hub.docker.com/v2/repositories/$IMAGE_NAME/tags/?digest=sha256:$CLEAN_SHA" \
    | jq -r '.results[0].name')
  
  if [ -z "$MANIFEST_REF" ] || [ "$MANIFEST_REF" = "null" ]; then
    echo "⚠️ No tag reference found for this digest"
    continue
  fi
  
  # 3. Delete using the tag reference
  DELETE_URL="https://hub.docker.com/v2/namespaces/${IMAGE_NAME%/*}/repositories/${IMAGE_NAME#*/}/tags/$MANIFEST_REF"
  echo "Deleting via tag reference: $MANIFEST_REF"
  
  RESPONSE=$(curl -v -s -o /dev/null -w "%{http_code}" -X DELETE \
    -H "Authorization: JWT $HUB_TOKEN" \
    -H "Accept: application/json" \
    "$DELETE_URL")
  
  # 4. Check response
  if [ "$RESPONSE" -eq 204 ]; then
    ((DELETED_MANIFESTS++))
    echo "✅ Successfully deleted via tag reference"
  else
    echo "❌ Failed to delete (HTTP $RESPONSE)"
    # Fallback to direct manifest delete
    echo "Attempting direct manifest delete..."
    RESPONSE=$(curl -v -s -o /dev/null -w "%{http_code}" -X DELETE \
      -H "Authorization: JWT $HUB_TOKEN" \
      -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
      "https://hub.docker.com/v2/repositories/$IMAGE_NAME/manifests/sha256:$CLEAN_SHA")
    
    if [ "$RESPONSE" -eq 202 ]; then
      ((DELETED_MANIFESTS++))
      echo "✅ Successfully deleted via direct manifest"
    else
      echo "❌ Fallback failed (HTTP $RESPONSE)"
    fi
  fi
  
  sleep 3
done
echo "Total manifests deleted: $DELETED_MANIFESTS/$MAX_DELETIONS"
