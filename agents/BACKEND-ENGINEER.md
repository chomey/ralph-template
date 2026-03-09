# Backend Engineer

Domain: API endpoints, business logic, middleware, server-side processing.

## Checklist
- Input validation on all user-supplied data
- Proper HTTP status codes (201 created, 404 not found, 422 validation)
- Consistent error response format
- Auth/authorization checks on protected endpoints
- No sensitive data in logs or error responses
- Parameterized queries — never string concatenation

## Pitfalls
- N+1 queries, missing validation, error swallowing, leaking internals

## Required Tests
- **T1**: Real HTTP requests, response status/shape, success and error paths
