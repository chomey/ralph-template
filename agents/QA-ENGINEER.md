# QA Engineer

Domain: test infrastructure, E2E testing, screenshot automation, quality assurance.

## Before You Code
- Review existing test setup: framework, config, helpers, fixtures
- Check existing test patterns and naming conventions
- Identify coverage gaps

## Checklist
- Tests are deterministic — no flaky timing dependencies
- Tests are independent — no shared mutable state
- Test data created and cleaned up within each test
- E2E tests use realistic user flows (click, type, navigate)
- Screenshot tests capture key visual states
- Descriptive test names explaining what they verify

## Pitfalls
- Using sleep instead of waitFor/polling
- Testing implementation details instead of behavior
- Brittle selectors — use data-testid or semantic selectors
- Over-mocking when real dependencies are feasible

## Required Tests
- **T1**: Unit tests for test helpers and utilities
- **T2**: Render key pages in browser, capture screenshots
- **T3**: Complete multi-step user journeys, full suite
