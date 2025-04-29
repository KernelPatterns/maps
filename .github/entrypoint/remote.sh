#!/usr/bin/env bash

# Authenticate with Docker Hub
echo "🔑 Authenticating with Docker Hub..."
HUB_TOKEN=$(curl -s -H "Content-Type: application/json" -X POST \
  -d "{\"username\": \"$HUB_USERNAME\", \"password\": \"$HUB_PASSWORD\"}" \
  https://hub.docker.com/v2/users/login/ | jq -r .token)

[ -z "$HUB_TOKEN" ] && { echo "❌ Authentication failed"; exit 1; }

# Extract namespace and repository
NAMESPACE=${IMAGE_NAME%/*}
REPO_NAME=${IMAGE_NAME#*/}

# Get oldest 15 manifests
echo "🔍 Fetching oldest $MAX_DELETIONS manifests..."
MANIFESTS=$(curl -s -H "Authorization: JWT $HUB_TOKEN" \
  "https://hub.docker.com/v2/repositories/$IMAGE_NAME/tags/?page_size=$MAX_DELETIONS&ordering=last_updated" \
  | jq -r '.results[] | select(.images != null) | .images[].digest' \
  | sort | uniq | head -n $MAX_DELETIONS)

# Delete manifests
DELETED=0
for SHA in $MANIFESTS; do
  echo "🗑️ Deleting manifest ${SHA:0:12}..."
  
  # Try deleting via manifest digest
  RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
    -H "Authorization: JWT $HUB_TOKEN" \
    -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
    "https://hub.docker.com/v2/repositories/$IMAGE_NAME/manifests/$SHA")
  
  if [ "$RESPONSE" -eq 202 ]; then
    ((DELETED++))
    echo "✅ Deleted successfully"
  else
    echo "❌ Failed to delete (HTTP $RESPONSE)"
  fi
  
  sleep 3  # Rate limiting
done

echo "🚀 Deletion completed: $DELETED/$MAX_DELETIONS manifests removed"
