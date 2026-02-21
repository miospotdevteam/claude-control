# UI Consistency Checklist

## Before

- [ ] Identify the project's design system or component library (check `src/components/ui/`, `@/components/`)
- [ ] Check for design tokens: colors, spacing, typography, breakpoints (Tailwind config, CSS variables, theme files)
- [ ] Read 2-3 existing pages/components similar to what you're building
- [ ] Check for shared layout components (headers, sidebars, page wrappers)
- [ ] Note responsive breakpoints and how existing components handle them

## During

- [ ] Use existing components before creating new ones — search first
- [ ] Use design tokens for colors, spacing, and typography — never hardcode values
- [ ] Follow the existing naming pattern for components and CSS classes
- [ ] Maintain consistent spacing: check what the codebase uses (p-4, gap-4, space-y-4, etc.)
- [ ] Match existing patterns for loading states, error states, and empty states
- [ ] If creating a new component: check if a similar one exists that can be extended

## After

- [ ] Compare your UI with existing pages for visual consistency
- [ ] Test responsive behavior at project breakpoints (mobile, tablet, desktop)
- [ ] Verify dark mode support if the project uses it
- [ ] Check accessibility: semantic HTML, keyboard navigation, screen reader labels
- [ ] Verify no hardcoded colors, font sizes, or spacing values

## Red Flags

| Pattern | Problem |
|---|---|
| Hardcoded hex colors instead of tokens | Drift from design system |
| New component duplicates existing one | Component bloat |
| Inconsistent spacing/padding | Visual inconsistency |
| Missing responsive handling | Broken on mobile |
| Inline styles when project uses utility classes | Convention violation |
| Custom fonts/sizes not from the theme | Typography drift |

## Deep Guidance

For comprehensive UI consistency strategy including design tokens, component
discipline, drift detection, and visual regression testing, read
`ui-consistency-guide.md`.

Look for installed skills about "frontend design" or "UI components" for
design-specific guidance.
