# Script Dispatcher for Complex Mocking Logic

The **Script Dispatcher** uses **Groovy scripts** to execute custom logic and decide which response to return. Use this when you need more control than JSON Body Dispatcher can provide.

---

## When to Use Script Dispatcher

### Use Script Dispatcher For:

- **Polymorphic request bodies** (oneOf + discriminator field)
  - Different message types → different responses

- **Multi-field logic**
  - Route based on combination of fields, ranges, or patterns

- **Stateful mocking**
  - Track request count, simulate rate limiting

- **GET/PATCH/DELETE operations**
  - Operations without request body or with complex query logic

- **Regex or pattern matching**
  - Match on path parameters, query strings, header values

### Don't Use Script Dispatcher For:

- Simple POST operations with distinct JSON payloads (use `json_body` instead)
- Operations that don't need conditional logic (no dispatcher needed)
- Operations that only need error header routing (use `script_header_error` instead)

---

## Groovy Script Contract

Microcks provides two objects to your Groovy script:

| Object | Type | Description |
|---|---|---|
| `mockRequest` | MockRequest | The incoming HTTP request |
| `requestContent` | String | Raw request body as string |

### MockRequest Methods

```groovy
mockRequest.method           // HTTP method (GET, POST, etc.)
mockRequest.path             // URL path
mockRequest.queryParameters  // Map<String, List<String>>
mockRequest.getParameter(name)  // Get query param value (String)
mockRequest.getParameters(name) // Get query param values (List<String>)
mockRequest.getRequestHeaders() // Map of headers
mockRequest.getHeader(name)     // Get header value (String)
```

### Response Matching

The script must **return one of the example names** (String). Microcks will then return the response with that example name.

```groovy
// Return the example name
"success"           // Returns the 'success' example
"invalid_input"     // Returns the 'invalid_input' example
"not_found"         // Returns the 'not_found' example
```

---

## OpenAPI Configuration

Mark the operation with the `x-mocking-microcks-dispatcher: script` vendor extension:

```yaml
paths:
  /events:
    post:
      operationId: submitEvent
      x-mocking-microcks-dispatcher: script
```

The import script loads the Groovy file from `mocking/dispatchers/{METHOD}-{path-slug}.groovy`.

For example, `POST /v1/orders/{orderId}/payments` → `mocking/dispatchers/POST-v1-orders-orderId-payments.groovy`.

---

## Complete Example: Polymorphic Message Dispatcher

**Scenario:** API accepts different message types (purchase, refund, update) and returns different responses.

```yaml
openapi: 3.0.0
info:
  title: Payment Events API
  version: 1.0.0

paths:
  /events:
    post:
      operationId: submitEvent
      x-mocking-microcks-dispatcher: script
      requestBody:
        required: true
        content:
          application/json:
            schema:
              oneOf:
                - $ref: '#/components/schemas/PurchaseEvent'
                - $ref: '#/components/schemas/RefundEvent'
            examples:
              purchase:
                value:
                  type: "purchase"
                  amount: 99.99
                  currency: "USD"
              refund:
                value:
                  type: "refund"
                  reason: "customer_request"
                  amount: 50.00
      responses:
        '202':
          description: Event accepted
          content:
            application/json:
              examples:
                purchase:
                  value:
                    event_id: "EVT-2025-001"
                    status: "processing"
                refund:
                  value:
                    event_id: "EVT-2025-002"
                    status: "refund_initiated"
        '400':
          description: Invalid event
          content:
            application/json:
              examples:
                unknown:
                  value:
                    error: "Unknown event type"

components:
  schemas:
    PurchaseEvent:
      type: object
      properties:
        type:
          const: "purchase"
        amount:
          type: number
        currency:
          type: string
    RefundEvent:
      type: object
      properties:
        type:
          const: "refund"
        reason:
          type: string
        amount:
          type: number
```

**Groovy file:** `mocking/dispatchers/POST-events.groovy`

```groovy
import groovy.json.JsonSlurper

def body = new JsonSlurper().parseText(requestContent)
def type = body.type ?: 'unknown'
return type
```

---

## Script Dispatcher Examples

### Example 1: Route by Query Parameter

```groovy
// Dispatcher rule: Parse 'role' query parameter
def role = mockRequest.getParameter('role') ?: 'user'
return role == 'admin' ? 'admin_view' : 'user_view'
```

**API Usage:**
```bash
# Returns 'admin_view' example
GET /data?role=admin

# Returns 'user_view' example
GET /data?role=user
```

### Example 2: Route by Request Body Field

```groovy
// Dispatcher rule: Parse JSON request body
import groovy.json.JsonSlurper

def body = new JsonSlurper().parseText(requestContent)
def status = body.status ?: 'draft'

switch (status) {
  case 'draft':
    return 'draft'
  case 'published':
    return 'published'
  default:
    return 'invalid_input'
}
```

### Example 3: Route by Range (Pagination)

```groovy
// Dispatcher rule: Simulate pagination based on 'page' query param
def page = mockRequest.getParameter('page')?.toInteger() ?: 1
def limit = mockRequest.getParameter('limit')?.toInteger() ?: 10

// First page returns 10 items, second page returns 5 items
if (page == 1 && limit == 10) {
  return 'page_1'
} else if (page == 2) {
  return 'page_2'
} else {
  return 'empty_page'
}
```

### Example 4: Route by Path Parameter (RESTful GET)

```groovy
// Dispatcher rule: Check path for user ID
def path = mockRequest.path
// Path: /users/123, /users/999, etc.

if (path.endsWith('/users/123')) {
  return 'user_found'
} else if (path.endsWith('/users/999')) {
  return 'user_not_found'
} else {
  return 'not_found'
}
```

### Example 5: Route by Header Value

```groovy
// Dispatcher rule: Check Accept header for format preference
def accept = mockRequest.getHeader('Accept') ?: 'application/json'

return accept.contains('xml') ? 'xml_response' : 'json_response'
```

---

## External Script Files

For complex logic, store scripts in external files following the convention:

**Convention:** `mocking/dispatchers/{METHOD}-{path-slug}.groovy`

**Examples:**
- `POST /events` → `mocking/dispatchers/POST-events.groovy`
- `POST /v1/orders/{orderId}/payments` → `mocking/dispatchers/POST-v1-orders-orderId-payments.groovy`
- `GET /users` → `mocking/dispatchers/GET-users.groovy`

The import script automatically loads these files when the operation has `x-mocking-microcks-dispatcher: script`.

---

## Troubleshooting Script Dispatcher

### Issue: Script syntax error

**Cause:** Groovy syntax error in dispatcher rule

**Solution:**
- Test the Groovy script locally: `groovy -e 'your code'`
- Check Microcks logs for error details
- Use simple logic first, then add complexity

### Issue: Wrong example returned

**Cause:** Script logic returns a name that doesn't exist in responses

**Solution:**
- Verify example names match exactly (case-sensitive)
- Add debug logging: `println("DEBUG: returning $result")`
- Check Microcks logs under `/admin`

### Issue: Request object is null

**Cause:** Groovy script doesn't have access to mockRequest

**Solution:**
- Microcks automatically injects `mockRequest` and `requestContent`
- Don't create them yourself
- Check Microcks version (needs 1.5.0+)

---

## Reference

- Microcks Dispatching: https://microcks.io/documentation/using/admin-features/#dispatching
- Groovy Language: https://groovy-lang.org/documentation.html
- Microcks GitHub Issues: https://github.com/microcks/microcks/issues
