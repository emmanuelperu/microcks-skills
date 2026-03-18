# JSON Body Dispatcher for POST Operations

The **JSON Body Dispatcher** allows Microcks to route requests based on fields in the request body. This is the preferred dispatcher for POST operations on collection endpoints where you need to distinguish between different request payloads.

---

## When to Use JSON Body Dispatcher

### Use JSON Body Dispatcher For:

- **POST to collection endpoints** (e.g., `POST /orders`, `POST /users`)
  - The dispatcher examines the request body to choose which response to return
  - Different payloads → different responses

- **Multiple examples of the same operation**
  - Success case: valid input → 201 Created
  - Error cases: invalid input → 400 Bad Request

### Don't Use JSON Body Dispatcher For:

- **GET, DELETE, PATCH** operations (use `script` dispatcher instead)
- **Endpoints without request body** (no body to inspect)
- **Operations with only one example** (no dispatching needed)

---

## How JSON Body Dispatcher Works

Microcks inspects the **request body** and tries to match it against your example payloads. The matching algorithm:

1. Serializes the incoming request body as JSON
2. Compares it (field-by-field) with each example payload
3. Returns the response for the **first matching example**
4. If no match found, returns a 404 or default error

### Finding the Discriminant Field

Microcks automatically detects which field(s) differ between examples and uses those as the **discriminant**.

**Example:**
```json
// success example
{ "status": "pending", "amount": 100 }

// invalid_input example
{ "status": "", "amount": -5 }
```

Microcks detects:
- `status` differs (empty vs non-empty)
- `amount` differs (negative vs positive)

When a request arrives with `status=""` → matches `invalid_input` example.

---

## Setting Up JSON Body Dispatcher

### Step 1: Enable Dispatcher in OpenAPI Spec

Add the vendor extension `x-mocking-microcks-dispatcher` to the operation:

```yaml
paths:
  /orders:
    post:
      operationId: createOrder
      x-mocking-microcks-dispatcher: json_body
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
                    - id: 1
                      qty: 2
                  total: 50.00
              invalid_input:
                value:
                  items: []
                  total: -10
      responses:
        '201':
          description: Created
          content:
            application/json:
              examples:
                success:
                  value:
                    orderId: 1001
                    status: "confirmed"
        '400':
          description: Invalid input
          content:
            application/json:
              examples:
                invalid_input:
                  value:
                    error: "Validation failed"
```

### Step 2: Verify Examples Are Complete

Ensure every example name in `requestBody.examples` has a **matching response example**:

| Example Name | Request Payload | Response Status |
|---|---|---|
| `success` | Valid order (qty > 0, total > 0) | 201 Created |
| `invalid_input` | Invalid order (empty items, negative total) | 400 Bad Request |

### Step 3: Import and Configure

Use the `microcks-import-artifacts` skill to import the spec. The import script automatically detects `x-mocking-microcks-dispatcher: json_body` and configures the JSON_BODY dispatcher via the Microcks API.

---

## Complete Example: E-commerce Orders API

```yaml
openapi: 3.0.0
info:
  title: Orders API
  version: 1.0.0

paths:
  /orders:
    post:
      operationId: createOrder
      x-mocking-microcks-dispatcher: json_body
      tags:
        - Orders
      description: Create a new order
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              properties:
                items:
                  type: array
                  items:
                    type: object
                    properties:
                      product_id:
                        type: integer
                      quantity:
                        type: integer
                total:
                  type: number
              required:
                - items
                - total
            examples:
              success:
                value:
                  items:
                    - product_id: 101
                      quantity: 2
                    - product_id: 102
                      quantity: 1
                  total: 250.50
              invalid_input:
                value:
                  items: []
                  total: -5
              invalid_quantity:
                value:
                  items:
                    - product_id: 101
                      quantity: -1
                  total: 100
      responses:
        '201':
          description: Order successfully created
          content:
            application/json:
              schema:
                type: object
                properties:
                  order_id:
                    type: string
                  status:
                    type: string
                  created_at:
                    type: string
                    format: date-time
              examples:
                success:
                  value:
                    order_id: "ORD-2025-001"
                    status: "confirmed"
                    created_at: "2025-03-17T10:30:00Z"
        '400':
          description: Validation error
          content:
            application/json:
              schema:
                type: object
                properties:
                  error:
                    type: string
                  details:
                    type: string
              examples:
                invalid_input:
                  value:
                    error: "Validation failed"
                    details: "Items list cannot be empty"
                invalid_quantity:
                  value:
                    error: "Validation failed"
                    details: "Quantity must be positive"
```

---

## Troubleshooting JSON Body Dispatcher

### Issue: Request doesn't match any example

**Cause:** Request payload doesn't exactly match any example (even slightly different structure or values)

**Solution:**
- Check that your request payload matches one of the examples exactly
- Use the Microcks UI to verify imported examples
- Add a catch-all `default` dispatcher rule if needed

### Issue: Dispatcher not triggering

**Cause:** `x-mocking-microcks-dispatcher: json_body` missing or misspelled

**Solution:**
- Verify the vendor extension is at the **operation level** (same level as `operationId`)
- Re-import the spec after adding the extension
- Use the Microcks API to verify dispatcher is set correctly

---

## Reference

- Microcks Dispatching: https://microcks.io/documentation/using/admin-features/#dispatching
- OpenAPI Specification: https://spec.openapis.org
