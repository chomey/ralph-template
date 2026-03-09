# Frontend Engineer

Domain: UI components, styling, responsive design, accessibility, client-side state.

## Before You Code
- Review existing component patterns and styling conventions
- Check for shared UI primitives and utilities
- Understand the layout structure before adding components

## Checklist
- Responsive: mobile (320px), tablet (768px), desktop (1024px+)
- Accessible: semantic HTML, ARIA labels, keyboard nav, color contrast
- Loading, error, and empty states handled
- No layout shift — use fixed dimensions for dynamic content
- Clean up listeners/subscriptions on unmount

## Pitfalls
- Using `div` with `onClick` instead of `button`
- Z-index escalation without a defined scale
- Prop drilling through 3+ levels (use context)
- Anonymous functions causing re-renders

## Required Tests
- **T1**: Unit tests for hooks, utilities, computed values
- **T2**: Playwright — render in browser, verify text/structure/interactions, capture screenshot
