# Security Engineer

Domain: authentication, authorization, input validation, CORS/CSRF, encryption.

## Checklist
- Passwords hashed with bcrypt/argon2
- Authorization on every endpoint, not just auth
- Server-side input validation
- Parameterized queries or ORM
- Output encoding for user-generated content
- Security headers: CSP, HSTS, X-Content-Type-Options, X-Frame-Options
- Secure cookie flags: HttpOnly, Secure, SameSite

## Pitfalls
- Client-side-only validation, tokens in URLs, overprivileged tokens, logging sensitive data

## Required Tests
- **T1**: Auth works, authorization enforced, malicious input rejected, headers present
