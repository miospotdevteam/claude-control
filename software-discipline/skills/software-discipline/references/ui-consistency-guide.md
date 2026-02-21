# UI Consistency Guide

Comprehensive guidance for maintaining visual consistency in user interfaces.
AI-generated code frequently introduces visual inconsistencies because it lacks
awareness of the existing design system.

---

## Design Tokens

Design tokens are the atomic values that define a visual system: colors,
spacing, typography, shadows, borders, breakpoints. They're the source of
truth for how things look.

### Primitive vs semantic tokens

**Primitive tokens** are raw values:
- `blue-500`, `gray-100`, `4px`, `16px`

**Semantic tokens** are named by purpose:
- `color-primary`, `color-background`, `spacing-sm`, `text-body`

**Always use semantic tokens when available.** They make the design system
resilient to changes — updating `color-primary` from blue to purple changes
every element that uses it.

### Where to find tokens

1. **Tailwind config** (`tailwind.config.js/ts`) — custom colors, spacing, fonts
2. **CSS variables** (`:root` in globals.css) — custom properties
3. **Theme files** (`theme.ts`, `tokens.ts`) — JavaScript theme objects
4. **Component library docs** — Shadcn/ui, MUI, Chakra theme docs

### Rules

- Never hardcode a color hex value — use a token
- Never hardcode a spacing pixel value — use a token/utility class
- Never hardcode a font size — use the type scale
- If you need a new value, ask whether it should be a new token

---

## Component Library Discipline

### Before creating a new component

1. Search `src/components/` for existing components
2. Check the UI library (Shadcn, MUI, Chakra) for built-in components
3. If a similar component exists, extend it — don't create a duplicate
4. If truly new, follow the existing component file structure exactly

### Component consistency patterns

- **Props interface**: Match the naming patterns of existing components
- **Default values**: Use the same defaults as sibling components
- **Variants**: Use the same variant naming (primary, secondary, destructive)
- **Sizes**: Use the same size naming (sm, md, lg)
- **States**: Handle the same states (loading, disabled, error)

### Common mistakes

- Creating `CustomButton` when the project has a `Button` component
- Using different spacing between similar components
- Inconsistent loading state implementations
- Missing disabled states
- Different error message positioning patterns

---

## Drift Detection

Drift = gradual visual inconsistency that accumulates over time. Each change
looks fine individually, but collectively they degrade the UI.

### How to detect drift

1. **Compare with siblings**: Does your new page/component look like the
   existing ones? Open them side by side.
2. **Check spacing rhythm**: Is the spacing between elements consistent with
   other pages? Look at gap, padding, margin values.
3. **Verify typography**: Are you using the same text sizes and weights as
   similar elements elsewhere?
4. **Test dark mode**: If the project supports dark mode, verify your changes
   work in both themes.

### Prevention

- Always read 2-3 existing similar components before building
- Use `Grep` to find how specific UI patterns are implemented elsewhere
- Copy the structure of existing pages when building new ones
- Match loading/empty/error states from existing implementations

---

## Visual Regression Testing

For projects that use visual regression testing (Playwright, Chromatic,
Percy, BackstopJS):

### Playwright screenshot testing

```typescript
// Compare against baseline screenshot
await expect(page).toHaveScreenshot('feature-name.png');

// Component-level screenshot
const component = page.getByRole('dialog');
await expect(component).toHaveScreenshot('dialog-variant.png');
```

### When to add visual tests

- New pages or major component changes
- Changes to shared components used in many places
- Changes to design tokens or theme values
- After fixing a visual bug (prevent regression)

### When NOT to add visual tests

- Internal layout changes that don't affect the user-facing UI
- Content changes (text updates, copy changes)
- Non-visual code changes (API handlers, utilities)

---

## Tailwind-Specific Guidance

- Check `tailwind.config` for custom values before using arbitrary values
- Use the project's existing spacing pattern (if everything uses p-4/p-6/p-8, don't introduce p-5)
- Maintain consistent responsive breakpoints (check what sm/md/lg/xl mean)
- Use component composition over complex utility chains
- Check for Tailwind plugins the project uses (typography, forms, etc.)
