---
name: microcks-openapi-mocking
description: Write OpenAPI examples that work with Microcks dispatchers for API mocking. Covers example pairing rules, JSON body dispatching, Groovy script dispatching, and dispatcher configuration via the Microcks API.
compatibility: Requires a running Microcks instance (see microcks-local-server skill)
---

# Microcks OpenAPI Mocking

Help write and configure OpenAPI specifications with examples that work correctly in Microcks.

## When to Use This Skill

Use this skill when:

- **Writing or editing named examples** in an OpenAPI spec for Microcks mocking
- **Adding a new endpoint** to an OpenAPI spec with multiple example scenarios (success, errors)
- **Configuring a dispatcher** to control how Microcks routes requests to different responses
- **Debugging a mock response** that isn't returning the expected data
- **Setting up example pairing** between request and response examples in OpenAPI

## Core Rules

Microcks mocking depends on correct **example pairing** and **dispatcher configuration**. Here are the key rules:

### Rule 1: Example Names Must Match Across Locations

Every named example in **path/query parameters** and **request body** must have a corresponding response example with the **same name**.

```yaml
paths:
  /pets/{petId}:
    get:
      parameters:
        - name: petId
          examples:
            success:      # ← example name
              value: 1
            not_found:    # ← example name
              value: 999
      responses:
        '200':
          content:
            application/json:
              examples:
                success:    # ← same name
                  value: { id: 1, name: Fluffy }
        '404':
          content:
            application/json:
              examples:
                not_found:  # ← same name
                  value: { error: Not found }
```

> **Details:** See [example-pairing.md](./references/example-pairing.md)

### Rule 2: No-Body Responses Need Content Block with `value: null`

Responses with no body (204, 304) must still have a `content` block with explicit `value: null`:

```yaml
delete:
  responses:
    '204':
      description: Deleted
      content:
        application/json:
          examples:
            success:
              value: null  # ← Required for no-body responses
```

### Rule 3: All Error Examples Need Input Examples

If you define an error response (400, 404, 500), there must be a matching **input example** (in parameters or requestBody) with the same example name that triggers it.

### Rule 4: POST on Collections → Use json_body Dispatcher

For `POST /resource` operations, use the `json_body` dispatcher to route requests based on the request body:

```yaml
paths:
  /orders:
    post:
      x-mocking-microcks-dispatcher: json_body  # ← Add this
      requestBody:
        content:
          application/json:
            examples:
              success:
                value: { total: 100, items: [{ id: 1 }] }
              invalid_input:
                value: { total: -5, items: [] }
```

> **Details:** See [json-body-dispatcher.md](./references/json-body-dispatcher.md)

### Rule 5: Operations Without Discriminant → Use script_header_error Dispatcher

For operations without a discriminating parameter or body (e.g., GET without query, POST with uniform body), use the `script_header_error` dispatcher. It routes on the HTTP `error` header:

```yaml
paths:
  /health:
    get:
      x-mocking-microcks-dispatcher: script_header_error
      responses:
        '200':
          content:
            application/json:
              examples:
                success:
                  value: { status: "healthy" }
        '400':
          content:
            application/json:
              examples:
                invalid_input:
                  value: { error: "Bad request" }
        '500':
          content:
            application/json:
              examples:
                server_error:
                  value: { error: "Internal server error" }
```

The import script generates a Groovy dispatcher that reads the `error` header:
- `error: 400` → returns `invalid_input`
- `error: 500` → returns `server_error`
- No header → returns `success`

### Rule 6: Complex Logic → Use script Dispatcher

For GET/PATCH/DELETE, polymorphic bodies, or multi-field routing logic, use the `script` dispatcher with an external Groovy file:

```yaml
paths:
  /events:
    post:
      x-mocking-microcks-dispatcher: script
```

The import script loads the Groovy file from `mocking/dispatchers/{METHOD}-{path-slug}.groovy`.

> **Details:** See [script-dispatcher.md](./references/script-dispatcher.md)

---

## Naming Conventions

Use these standard example names to keep your specs consistent:

| Example Name | HTTP Status | Meaning |
|---|---|---|
| `success` | 200, 201, 204 | Successful request |
| `invalid_input` | 400 | Request validation failed |
| `unauthorized` | 401 | Authentication required |
| `forbidden` | 403 | Authorization failed |
| `not_found` | 404 | Resource not found |
| `conflict` | 409 | Conflict (e.g., duplicate) |
| `server_error` | 500 | Server error |
| `unavailable` | 503 | Service unavailable |

---

## Quick Reference: Dispatcher Types

| Dispatcher | When to Use | Example |
|---|---|---|
| `json_body` | POST operations; route by request body fields | [json-body-dispatcher.md](./references/json-body-dispatcher.md) |
| `script_header_error` | Operations without discriminating param/body; route by `error` header | See Rule 5 above |
| `script` | Complex logic; route by query params, headers, path, or body | [script-dispatcher.md](./references/script-dispatcher.md) |

---

## Step-by-Step: Create a Complete Example

### 1. Define the Operation with Examples

```yaml
openapi: 3.0.0
info:
  title: User API
  version: 1.0.0

paths:
  /users:
    post:
      operationId: createUser
      x-mocking-microcks-dispatcher: json_body  # Enable dispatching
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/User'
            examples:
              success:                   # ← Example name
                value:
                  name: "Alice"
                  email: "alice@example.com"
              invalid_input:             # ← Example name
                value:
                  name: ""
                  email: "not-an-email"
      responses:
        '201':
          description: User created
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/User'
              examples:
                success:                 # ← Must match request
                  value:
                    id: 1
                    name: "Alice"
                    email: "alice@example.com"
        '400':
          description: Invalid input
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Error'
              examples:
                invalid_input:           # ← Must match request
                  value:
                    error: "Validation failed"
                    fields:
                      - "name cannot be empty"
                      - "email must be valid"
```

### 2. Import and Configure

Use the `microcks-import-artifacts` skill to import the spec and auto-configure dispatchers:

```bash
./mocking/import-openapi.sh path/to/api-spec.yaml
```

### 3. Test the Mock

```bash
# Should return 201 with 'success' example
curl -X POST http://localhost:8080/api/mocks/User%20API/1.0.0/users \
  -H "Content-Type: application/json" \
  -d '{"name": "Alice", "email": "alice@example.com"}'

# Should return 400 with 'invalid_input' example
curl -X POST http://localhost:8080/api/mocks/User%20API/1.0.0/users \
  -H "Content-Type: application/json" \
  -d '{"name": "", "email": "not-an-email"}'
```

---

## Reference Files

- **[example-pairing.md](./references/example-pairing.md)** — Rules for matching request and response examples
- **[json-body-dispatcher.md](./references/json-body-dispatcher.md)** — Route POST requests based on request body
- **[script-dispatcher.md](./references/script-dispatcher.md)** — Complex routing with Groovy scripts
- **[dispatcher-setup.md](./references/dispatcher-setup.md)** — Configure dispatchers via Microcks REST API

---

## Common Patterns

### Pattern 1: GET by ID (with not found case)

```yaml
paths:
  /users/{userId}:
    get:
      parameters:
        - name: userId
          in: path
          examples:
            success:
              value: 1
            not_found:
              value: 999
      responses:
        '200':
          content:
            application/json:
              examples:
                success:
                  value: { id: 1, name: Alice }
        '404':
          content:
            application/json:
              examples:
                not_found:
                  value: { error: User not found }
```

### Pattern 2: POST with Validation Errors

```yaml
paths:
  /products:
    post:
      x-mocking-microcks-dispatcher: json_body
      requestBody:
        content:
          application/json:
            examples:
              success:
                value: { sku: "ABC123", price: 29.99 }
              invalid_input:
                value: { sku: "", price: -5 }
      responses:
        '201':
          content:
            application/json:
              examples:
                success:
                  value: { id: 1, sku: ABC123, price: 29.99 }
        '400':
          content:
            application/json:
              examples:
                invalid_input:
                  value: { error: Validation failed }
```

### Pattern 3: DELETE with 204 No Content

```yaml
paths:
  /products/{productId}:
    delete:
      parameters:
        - name: productId
          examples:
            success:
              value: 1
      responses:
        '204':
          description: Deleted
          content:
            application/json:
              examples:
                success:
                  value: null
```

---

## Troubleshooting

### Mock Not Returning Expected Response

**Check:**
1. Are request/response examples named the same? (case-sensitive)
2. Is the dispatcher configured? (check Microcks Admin UI)
3. Does your request match an example exactly?

**Solution:** See [example-pairing.md](./references/example-pairing.md) and [dispatcher-setup.md](./references/dispatcher-setup.md)

### Dispatcher Not Triggering

**Check:**
1. Is `x-mocking-microcks-dispatcher` correctly spelled and at operation level?
2. Have you re-imported the spec after adding the dispatcher?

**Solution:** See [json-body-dispatcher.md](./references/json-body-dispatcher.md) or [script-dispatcher.md](./references/script-dispatcher.md)

### Script Dispatcher Returns Wrong Example

**Check:**
1. Does the script return a valid example name (must exist in responses)?
2. Is the Groovy syntax correct?

**Solution:** See [script-dispatcher.md](./references/script-dispatcher.md) "Troubleshooting"

---

## Complementary Skills

- **[microcks-local-server](microcks-local-server)** — Start a local Microcks server with Docker Compose
  ```bash
  npx skills add emmanuelperu/microcks-skills --skill microcks-local-server
  ```

- **[microcks-import-artifacts](microcks-import-artifacts)** — Import OpenAPI specs into Microcks and auto-configure dispatchers
  ```bash
  npx skills add emmanuelperu/microcks-skills --skill microcks-import-artifacts
  ```

- **[openapi-spec-generation](openapi-spec-generation)** — Write high-quality OpenAPI specifications from scratch
  ```bash
  npx skills add https://github.com/wshobson/agents --skill openapi-spec-generation
  ```

---

## Related

- **Microcks Documentation:** https://microcks.io/documentation
- **OpenAPI Specification:** https://spec.openapis.org
- **Groovy Language:** https://groovy-lang.org
