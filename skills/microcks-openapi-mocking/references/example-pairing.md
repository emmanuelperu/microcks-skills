# Example Pairing Rules for OpenAPI + Microcks

When Microcks imports an OpenAPI specification, it uses **named examples** to match parameters, request bodies, and responses. This document explains the rules for creating compatible examples.

---

## Rule 1: Example Names Must Match Across All Locations

For Microcks to correctly pair a request example with a response example, the **same example name** must appear in:
- Path parameters (`parameters` with `in: path`)
- Query parameters (`parameters` with `in: query`)
- Request body (`requestBody.content[].examples`)
- Response bodies (`responses[].content[].examples`)

### ✅ Good Example: GET with Path Parameter

```yaml
paths:
  /pets/{petId}:
    get:
      operationId: getPetById
      parameters:
        - name: petId
          in: path
          required: true
          schema:
            type: integer
          examples:
            success:
              value: 42
            not_found:
              value: 999
      responses:
        '200':
          description: Pet found
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Pet'
              examples:
                success:
                  value:
                    id: 42
                    name: "Fluffy"
                    species: "cat"
        '404':
          description: Pet not found
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Error'
              examples:
                not_found:
                  value:
                    error: "Pet not found"
                    code: 404
```

**Microcks logic:**
- When `petId=42` → matches example `success` → returns `200` response with example `success`
- When `petId=999` → matches example `not_found` → returns `404` response with example `not_found`

---

### ✅ Good Example: POST with Request Body

```yaml
paths:
  /users:
    post:
      operationId: createUser
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/User'
            examples:
              success:
                value:
                  name: "Alice"
                  email: "alice@example.com"
              invalid_input:
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
                success:
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
                invalid_input:
                  value:
                    error: "Validation failed"
                    fields:
                      - email: "invalid format"
```

---

## Rule 2: Responses Without Body Must Have a Content Block with `value: null`

Some endpoints return no body (e.g., `204 No Content`, `204` Delete success). Microcks still expects a `content` block with an explicit `value: null` for the example.

### ✅ Good Example: DELETE with 204 No Content

```yaml
paths:
  /users/{userId}:
    delete:
      operationId: deleteUser
      parameters:
        - name: userId
          in: path
          required: true
          schema:
            type: integer
          examples:
            success:
              value: 1
      responses:
        '204':
          description: User deleted
          content:
            application/json:
              examples:
                success:
                  value: null
```

### ❌ Bad Example: No Content Block

```yaml
responses:
  '204':
    description: User deleted
    # ❌ Missing content block — Microcks won't pair this correctly
```

---

## Rule 3: Error Examples Must Have Corresponding Input Examples

If an endpoint returns an error response (400, 404, 500), there **must be** a matching input example that triggers it.

For path/query parameters, this means having the same example name in parameters **and** in the error response.

### ✅ Complete Example: POST with Multiple Outcomes

```yaml
paths:
  /orders:
    post:
      operationId: createOrder
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/Order'
            examples:
              success:
                value:
                  items:
                    - product_id: 1
                      quantity: 2
                  total: 100.00
              invalid_input:
                value:
                  items: []
                  total: -10
              insufficient_stock:
                value:
                  items:
                    - product_id: 999
                      quantity: 1000
                  total: 99999.99
      responses:
        '201':
          description: Order created
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Order'
              examples:
                success:
                  value:
                    id: 1001
                    items:
                      - product_id: 1
                        quantity: 2
                    total: 100.00
                    status: "confirmed"
        '400':
          description: Validation failed
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Error'
              examples:
                invalid_input:
                  value:
                    error: "Validation failed"
                    details: "Items cannot be empty"
        '422':
          description: Insufficient stock
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Error'
              examples:
                insufficient_stock:
                  value:
                    error: "Insufficient stock"
                    product_id: 999
```

---

## Summary Checklist

When adding a new operation with examples:

- [ ] Every example name in `parameters[].examples` also appears in a response
- [ ] Every example name in `requestBody.content[].examples` also appears in a response
- [ ] Every error response has an example with a matching name in parameters/requestBody
- [ ] Responses with no body (204, 304, etc.) have `content` with `value: null`
- [ ] All response examples have matching names in request examples

---

## Reference

- Microcks Documentation: https://microcks.io/documentation
- OpenAPI Specification: https://spec.openapis.org/oas/v3.0.3#example-object
