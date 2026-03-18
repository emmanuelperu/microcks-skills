# Dispatcher Configuration via Microcks API

After importing an OpenAPI spec into Microcks, you can configure or refine the dispatcher settings using the REST API. This is useful for post-import adjustments or automation in CI/CD pipelines.

---

## Dispatcher Types

| Dispatcher | Vendor Extension Value | Use Case |
|---|---|---|
| `JSON_BODY` | `json_body` | POST operations on collections; route by request body fields |
| `SCRIPT` | `script` or `script_header_error` | Complex logic; route by query params, headers, path, or body structure |
| `XPATH` | — | XML-based APIs; route by XML element values |
| `REGEX` | — | Route by regex patterns on path or query params |
| `FALLBACK` | — | Default dispatcher (no special logic) |

---

## Microcks API Endpoint

### GET Service Details

First, find your service ID:

```bash
curl -X GET http://localhost:8080/api/services \
  -H "Accept: application/json"
```

Response (example):
```json
{
  "content": [
    {
      "id": "5f1a2b3c4d5e6f7a8b9c0d1e",
      "name": "Orders API",
      "version": "1.0.0"
    }
  ]
}
```

### Configure Dispatcher for Operation

```bash
curl -X PUT http://localhost:8080/api/services/{serviceId}/operation \
  -H "Content-Type: application/json" \
  -d '{
    "name": "createOrder",
    "method": "POST",
    "dispatcher": "JSON_BODY",
    "dispatcherRules": "total>0;items.size()"
  }'
```

---

## JSON_BODY Dispatcher Configuration

### Payload Structure

```json
{
  "name": "createOrder",
  "method": "POST",
  "dispatcher": "JSON_BODY",
  "dispatcherRules": "field1;field2;field3"
}
```

- **name**: Operation ID from OpenAPI
- **method**: HTTP method (POST, GET, etc.)
- **dispatcher**: "JSON_BODY"
- **dispatcherRules**: Semicolon-separated field paths used for matching
  - `amount` — simple field
  - `items.size()` — array length
  - `type` — field name

### Complete Example

```bash
curl -X PUT http://localhost:8080/api/services/{serviceId}/operation \
  -H "Content-Type: application/json" \
  -d '{
    "name": "createOrder",
    "method": "POST",
    "dispatcher": "JSON_BODY",
    "dispatcherRules": "total;items.size()"
  }'
```

This configures Microcks to distinguish orders by:
1. `total` field value
2. `items` array size

---

## SCRIPT Dispatcher Configuration

### Payload Structure

```json
{
  "name": "submitEvent",
  "method": "POST",
  "dispatcher": "SCRIPT",
  "dispatcherRules": "return mockRequest.getParameter(\"type\") ?: \"unknown\""
}
```

- **dispatcher**: "SCRIPT"
- **dispatcherRules**: Inline Groovy script (single line or multiline)

### Multiline Script

For complex logic, use JSON escaping for newlines:

```bash
curl -X PUT http://localhost:8080/api/services/{serviceId}/operation \
  -H "Content-Type: application/json" \
  -d '{
    "name": "submitEvent",
    "method": "POST",
    "dispatcher": "SCRIPT",
    "dispatcherRules": "def type = mockRequest.getParameter(\"type\");\nreturn type ? type : \"unknown\";"
  }'
```

---

## Workflow: Import Spec → Detect → Configure

### Step 1: Import OpenAPI Spec

```bash
curl -X POST http://localhost:8080/api/artifact/upload \
  -F 'file=@api-spec.yaml' \
  -F 'mainArtifact=true'
```

### Step 2: List Services

```bash
curl -X GET http://localhost:8080/api/services \
  -H "Accept: application/json" | jq '.content[] | {id: .id, name: .name}'
```

Output:
```json
{
  "id": "abc123",
  "name": "Orders API"
}
```

### Step 3: List Operations

```bash
curl -X GET http://localhost:8080/api/services/abc123/operations \
  -H "Accept: application/json"
```

Output:
```json
[
  {
    "name": "createOrder",
    "method": "POST",
    "dispatcher": "FALLBACK",
    "dispatcherRules": null
  }
]
```

### Step 4: Configure Dispatcher

```bash
curl -X PUT http://localhost:8080/api/services/abc123/operation \
  -H "Content-Type: application/json" \
  -d '{
    "name": "createOrder",
    "method": "POST",
    "dispatcher": "JSON_BODY",
    "dispatcherRules": "total;items.size()"
  }'
```

### Step 5: Verify Configuration

```bash
curl -X GET http://localhost:8080/api/services/abc123/operations \
  -H "Accept: application/json"
```

---

## Automated Configuration

The `microcks-import-artifacts` skill provides an `import-openapi.sh` script that automates this entire workflow. It reads `x-mocking-microcks-dispatcher` vendor extensions from your OpenAPI spec and automatically configures the appropriate dispatchers via the Microcks API.

See the [microcks-import-artifacts](../../microcks-import-artifacts/) skill for details.

---

## Troubleshooting API Configuration

### Issue: 404 Service Not Found

**Cause:** Service ID is wrong or service not imported yet

**Solution:**
```bash
# List all services to verify
curl -s -X GET http://localhost:8080/api/services | jq '.content[] | {id, name}'
```

### Issue: 400 Bad Request

**Cause:** Invalid dispatcher or operation name

**Solution:**
- Verify operation name matches exactly (case-sensitive)
- Check dispatcher spelling (JSON_BODY, not json_body)
- Verify HTTP method is correct

### Issue: Dispatcher rules not working

**Cause:** Rule syntax error or field doesn't exist in examples

**Solution:**
- Check Microcks logs: `docker logs microcks`
- Verify examples exist with the names you're targeting
- Test Groovy syntax locally for SCRIPT dispatcher

---

## Reference

- Microcks API Documentation: https://microcks.io/documentation/rest-api/
- OpenAPI 3.0 Specification: https://spec.openapis.org/oas/v3.0.3
