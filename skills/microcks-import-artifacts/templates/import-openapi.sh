#!/bin/bash
set -e

# Import an OpenAPI specification into Microcks and auto-configure dispatchers
# based on x-mocking-microcks-dispatcher vendor extensions.
#
# Usage:
#   ./import-openapi.sh path/to/api-spec.yaml
#
# Environment variables:
#   MICROCKS_URL  - Microcks base URL (default: http://localhost:8080)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Arguments ────────────────────────────────────────────────────────
SPEC_FILE="${1:?Usage: $0 <path-to-openapi-spec>}"

if [ ! -f "$SPEC_FILE" ]; then
  echo "Error: spec file not found: $SPEC_FILE"
  exit 1
fi

# Resolve to absolute path
SPEC_FILE="$(cd "$(dirname "$SPEC_FILE")" && pwd)/$(basename "$SPEC_FILE")"

# ── Configuration ────────────────────────────────────────────────────
MICROCKS_URL="${MICROCKS_URL:-http://localhost:8080}"
MICROCKS_API="${MICROCKS_URL}/api"

# Platform flag for Apple Silicon
PLATFORM=""
if [[ $(uname -s) == "Darwin" ]] && [[ $(uname -m) == "arm64" ]]; then
  PLATFORM="--platform linux/amd64"
fi

# ── Health check ─────────────────────────────────────────────────────
echo "Checking Microcks at ${MICROCKS_URL}..."

if ! curl -s -o /dev/null --connect-timeout 5 "${MICROCKS_API}"; then
  echo ""
  echo "Error: Microcks is not running at ${MICROCKS_URL}"
  echo ""
  echo "Start Microcks first:"
  echo "  docker compose -f mocking/docker-compose.yml up -d"
  echo ""
  echo "Or set MICROCKS_URL if using a different address:"
  echo "  MICROCKS_URL=http://localhost:9080 $0 $1"
  exit 1
fi

echo "Microcks is running."

# ── Download microcks-cli if needed ──────────────────────────────────
if [ ! -x "$SCRIPT_DIR/microcks-cli" ]; then
  echo ""
  echo "microcks-cli not found, downloading..."
  "$SCRIPT_DIR/download-microcks-cli.sh"
fi

# ── Import the spec ──────────────────────────────────────────────────
echo ""
echo "Importing spec: $SPEC_FILE"

"$SCRIPT_DIR/microcks-cli" import \
  "${SPEC_FILE}:true" \
  --microcksURL="${MICROCKS_API}" \
  --keycloakClientId=foo \
  --keycloakClientSecret=bar

# ── Get service ID ───────────────────────────────────────────────────
SERVICE_LIST=$(curl -s "${MICROCKS_API}/services?page=0&size=1")
SERVICE_ID=$(echo "$SERVICE_LIST" | jq -r '.[0].id')

if [ -z "$SERVICE_ID" ] || [ "$SERVICE_ID" = "null" ]; then
  echo "Error: could not find service ID after import."
  exit 1
fi

echo "Service ID: $SERVICE_ID"

# ── Helper: convert YAML spec to JSON ────────────────────────────────
spec_to_json() {
  docker run --rm $PLATFORM \
    -v "$(dirname "$SPEC_FILE"):/work" \
    mikefarah/yq -o json '.' "/work/$(basename "$SPEC_FILE")"
}

# ── Configure dispatchers ───────────────────────────────────────────
echo ""
echo "=== Configuring custom Microcks dispatchers ==="

SPEC_JSON=$(spec_to_json)

# Find all operations with x-mocking-microcks-dispatcher
DISPATCHED_OPERATIONS=$(echo "$SPEC_JSON" | jq -r '
  .paths | to_entries[] | .key as $path |
  .value | to_entries[] |
  select(.value."x-mocking-microcks-dispatcher" != null) |
  "\(.key | ascii_upcase) \($path) \(.value."x-mocking-microcks-dispatcher")"
')

if [ -z "$DISPATCHED_OPERATIONS" ]; then
  echo "No operations with x-mocking-microcks-dispatcher found."
else
  while IFS= read -r line; do
    METHOD=$(echo "$line" | awk '{print $1}')
    PATH_SPEC=$(echo "$line" | awk '{print $2}')
    DISPATCHER_TYPE=$(echo "$line" | awk '{print $3}')

    echo ""
    echo "--- $METHOD $PATH_SPEC (dispatcher: $DISPATCHER_TYPE) ---"

    OPERATION_NAME="${METHOD} ${PATH_SPEC}"
    OPERATION_NAME_ENCODED=$(echo "$OPERATION_NAME" | sed 's/ /%20/g; s/{/%7b/g; s/}/%7d/g')

    if [ "$DISPATCHER_TYPE" = "script_header_error" ]; then
      # SCRIPT dispatcher: route based on the "error" HTTP header
      read -r -d '' GROOVY_SCRIPT << 'GROOVY_EOF' || true
def headers = mockRequest.getRequestHeaders()
log.info("headers: " + headers)
if (headers.hasValues("error")) {
   def error = headers.get("error", "null")
   switch(error) {
      case "400":
         return "invalid_input";
      case "500":
         return "server_error";
   }
}
return "success"
GROOVY_EOF

      curl -s -g "${MICROCKS_API}/services/$SERVICE_ID/operation?operationName=$OPERATION_NAME_ENCODED" \
        -X 'PUT' \
        -H 'Content-Type: application/json' \
        --data-raw "{\"defaultDelay\":0,\"dispatcher\":\"SCRIPT\",\"dispatcherRules\":$(printf '%s' "$GROOVY_SCRIPT" | jq -Rs .),\"parameterConstraints\":[]}" \
        > /dev/null

      echo "  SCRIPT (header error) dispatcher pushed."

    elif [ "$DISPATCHER_TYPE" = "script" ]; then
      # SCRIPT dispatcher with external Groovy file
      # Convention: mocking/dispatchers/{METHOD}-{path-slug}.groovy
      SLUG=$(echo "$PATH_SPEC" | sed 's|^/||; s|/|-|g; s|[{}]||g')
      GROOVY_FILE="$SCRIPT_DIR/dispatchers/${METHOD}-${SLUG}.groovy"

      # Also check project-root relative path
      if [ ! -f "$GROOVY_FILE" ]; then
        GROOVY_FILE="$PROJECT_ROOT/mocking/dispatchers/${METHOD}-${SLUG}.groovy"
      fi

      if [ ! -f "$GROOVY_FILE" ]; then
        echo "  Groovy file not found: dispatchers/${METHOD}-${SLUG}.groovy, skipping."
        continue
      fi

      GROOVY_SCRIPT=$(cat "$GROOVY_FILE")

      curl -s -g "${MICROCKS_API}/services/$SERVICE_ID/operation?operationName=$OPERATION_NAME_ENCODED" \
        -X 'PUT' \
        -H 'Content-Type: application/json' \
        --data-raw "{\"defaultDelay\":0,\"dispatcher\":\"SCRIPT\",\"dispatcherRules\":$(printf '%s' "$GROOVY_SCRIPT" | jq -Rs .),\"parameterConstraints\":[]}" \
        > /dev/null

      echo "  SCRIPT dispatcher pushed (from $GROOVY_FILE)."

    elif [ "$DISPATCHER_TYPE" = "json_body" ]; then
      # JSON_BODY dispatcher: detect discriminant field from examples
      METHOD_LOWER=$(echo "$METHOD" | tr '[:upper:]' '[:lower:]')

      EXAMPLE_NAMES=$(echo "$SPEC_JSON" | jq -r "
        .paths[\"$PATH_SPEC\"].$METHOD_LOWER.requestBody.content.\"application/json\".examples | keys | .[]
      " 2>/dev/null)

      if [ -z "$EXAMPLE_NAMES" ]; then
        echo "  No requestBody examples found, skipping."
        continue
      fi

      EXAMPLE_COUNT=$(echo "$EXAMPLE_NAMES" | wc -l | tr -d ' ')
      if [ "$EXAMPLE_COUNT" -lt 2 ]; then
        echo "  Only one example, no dispatching needed."
        continue
      fi

      # Find the first field that differs across examples
      FIRST_EXAMPLE=$(echo "$EXAMPLE_NAMES" | head -1)

      FIELDS=$(echo "$SPEC_JSON" | jq -r "
        .paths[\"$PATH_SPEC\"].$METHOD_LOWER.requestBody.content.\"application/json\".examples.$FIRST_EXAMPLE.value | keys | .[]
      " 2>/dev/null)

      DISPATCH_FIELD=""
      for field in $FIELDS; do
        UNIQUE_VALUES=$(echo "$SPEC_JSON" | jq -r "
          .paths[\"$PATH_SPEC\"].$METHOD_LOWER.requestBody.content.\"application/json\".examples
          | to_entries[]
          | .value.value.$field
          | tostring
        " 2>/dev/null | sort -u | wc -l | tr -d ' ')

        if [ "$UNIQUE_VALUES" -ge "$EXAMPLE_COUNT" ]; then
          DISPATCH_FIELD="$field"
          break
        fi
      done

      if [ -z "$DISPATCH_FIELD" ]; then
        for field in $FIELDS; do
          UNIQUE_VALUES=$(echo "$SPEC_JSON" | jq -r "
            .paths[\"$PATH_SPEC\"].$METHOD_LOWER.requestBody.content.\"application/json\".examples
            | to_entries[]
            | .value.value.$field
            | tostring
          " 2>/dev/null | sort -u | wc -l | tr -d ' ')

          if [ "$UNIQUE_VALUES" -gt 1 ]; then
            DISPATCH_FIELD="$field"
            break
          fi
        done
      fi

      if [ -z "$DISPATCH_FIELD" ]; then
        echo "  No differentiating field found, skipping."
        continue
      fi

      echo "  Dispatching on field: /$DISPATCH_FIELD"

      # Build the cases JSON
      CASES="{"
      FIRST=true
      for example_name in $EXAMPLE_NAMES; do
        FIELD_VALUE=$(echo "$SPEC_JSON" | jq -r "
          .paths[\"$PATH_SPEC\"].$METHOD_LOWER.requestBody.content.\"application/json\".examples.$example_name.value.$DISPATCH_FIELD | tostring
        " 2>/dev/null)

        if [ "$FIRST" = true ]; then
          FIRST=false
        else
          CASES="$CASES,"
        fi
        CASES="$CASES \"$FIELD_VALUE\": \"$example_name\""
      done
      CASES="$CASES, \"default\": \"$FIRST_EXAMPLE\"}"

      DISPATCHER_RULES=$(jq -n \
        --arg exp "/$DISPATCH_FIELD" \
        --arg op "equals" \
        --argjson cases "$CASES" \
        '{exp: $exp, operator: $op, cases: $cases}' | jq -c .)

      echo "  Rules: $DISPATCHER_RULES"

      curl -s -g "${MICROCKS_API}/services/$SERVICE_ID/operation?operationName=$OPERATION_NAME_ENCODED" \
        -X 'PUT' \
        -H 'Content-Type: application/json' \
        --data-raw "{\"defaultDelay\":0,\"dispatcher\":\"JSON_BODY\",\"dispatcherRules\":$(echo "$DISPATCHER_RULES" | jq -Rs .),\"parameterConstraints\":[]}" \
        > /dev/null

      echo "  JSON_BODY dispatcher pushed."

    else
      echo "  Unknown dispatcher type '$DISPATCHER_TYPE', skipping."
    fi

  done <<< "$DISPATCHED_OPERATIONS"
fi

echo ""
echo "=== Import complete ==="
echo "Microcks UI: ${MICROCKS_URL}"
