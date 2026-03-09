# Full Stack Engineer

Domain: end-to-end feature implementation spanning frontend and backend.

## Before You Code
- Trace the data flow: UI → state → computation → display
- Check for existing shared types, utilities, and patterns
- Define the data contract before implementing

## Checklist
- Frontend and backend validation rules match
- Loading, error, and empty states handled in UI
- No N+1 queries or redundant computations
- TypeScript types consistent across boundaries
- Both UI and logic changes in the same commit

## Pitfalls
- Frontend/backend type mismatch
- Missing error handling surfaced to user
- Race conditions from rapid state updates
- Over-fetching data the UI doesn't need

## Required Tests
- **T1**: Unit tests for logic, computations, and state transformations
- **T2**: Playwright — render component, verify visible output and interactions
