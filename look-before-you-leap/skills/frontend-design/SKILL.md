---
name: frontend-design
description: "Create distinctive, production-grade frontend interfaces. Detects greenfield vs integration mode, uses a 6-axis decision matrix for aesthetic direction, provides framework-specific implementation guidance, and verifies quality through accessibility, responsive, performance, and coherence checklists. Use when building or designing web components, pages, or applications. Do NOT use when: fixing a CSS bug with no design change, brainstorming without implementation intent (use brainstorming instead), or making backend-only changes. When brainstorming preceded this skill, skip Phases 1-2 and start at Phase 3."
---

# Frontend Design

Build frontend interfaces that are distinctive, intentional, and
production-grade. This skill replaces vague "be creative" advice with a
structured process that produces consistently high-quality results while
preventing the generic aesthetic convergence that plagues AI-generated UIs.

**Announce at start:** "I'm using the frontend-design skill to guide the
design and implementation."

---

## Prerequisites

This skill operates within the conductor's Step 1-3:

- **Phase 1** (Context Scan) runs during Step 1 (Explore) and feeds
  `discovery.md`.
- **Phase 2** (Design Direction) runs between Step 1 and Step 2 — its
  outputs are consumed by `writing-plans` when creating the masterPlan.
- **Phases 3-4** (Implementation, Verification) run during Step 3 (Execute).

---

## Integration with Brainstorming

If `brainstorming` ran first and produced a `design.md` with visual
direction (typography, colors, layout choices): **skip Phases 1-2 entirely**.
Use the approved design and proceed to Phase 3.

If no brainstorming preceded this skill: run Phases 1-2 (with the user
approval checkpoint in Phase 2).

If the user's request is purely "build this mockup/design" (design already
decided): skip Phase 2, proceed to Phase 3.

---

## Phase 1: Context Scan

Determine the operating mode before making any design decisions.

### Detect the mode

**Greenfield mode** — you have full creative freedom:
- Building a standalone page, component, or prototype
- No `tailwind.config` custom theme, no CSS variables, no component library,
  no theme files
- User explicitly says "from scratch" or "new design"

**Integration mode** — you work within an existing system:
- Project has Tailwind config with custom theme, CSS variables, or a
  component library
- Existing pages/components establish clear patterns
- User is adding to or modifying an existing UI

### Greenfield scan

Note these before proceeding:
- **Framework**: vanilla HTML/CSS, React, Vue, Svelte, etc.
- **Constraints**: must work without JS? SSR-compatible? Performance budget?
- **Delivery format**: single HTML file? Component library? Full app?
- **Audience and purpose**: who uses this and why?

### Integration scan

Read these before proceeding:
- `tailwind.config` / CSS variables / theme files — extract the token system
- 2-3 existing pages/components — learn the visual language
- Component library docs (Shadcn, MUI, Chakra, etc.) — know what's available
- Note what's working well and what could be elevated

In integration mode, also read:
- `references/ui-consistency-checklist.md` — consistency rules
- `references/ui-consistency-guide.md` — design token discipline

**Both modes:** Write findings to `discovery.md` as part of the conductor's
Step 1 exploration.

**Failure path:** If the project has no discernible design system and isn't
greenfield (e.g., inconsistent styles, no tokens), treat it as greenfield
with the constraint of matching existing code conventions.

---

## Phase 2: Design Direction

### Greenfield — Decision Matrix

Score each axis on a 1-5 scale based on the project context. The combination
narrows the aesthetic space before any visual decisions are made.

| Axis | 1 | 5 |
|---|---|---|
| **Audience** | Technical / developer | General public / consumer |
| **Formality** | Corporate / institutional | Casual / personal |
| **Energy** | Calm / restrained | Dynamic / energetic |
| **Density** | Spacious / minimal | Dense / information-rich |
| **Era** | Classic / timeless | Contemporary / trendy |
| **Temperature** | Warm (organic, rounded) | Cool (geometric, precise) |

**Example:** A developer documentation site — Technical (5), Formal (3),
Calm (4), Dense (4), Contemporary (4), Cool (5) — narrows to:
monospace-influenced typography, cool neutral palette with one accent, generous
line-height but compact layout, subtle animations, geometric shapes.

**Example:** A children's educational app — General (5), Casual (5),
Energetic (5), Spacious (2), Contemporary (4), Warm (5) — narrows to:
rounded display font, bright primary palette, generous whitespace, bouncy
animations, organic shapes.

#### Creative seed protocol

After scoring the axes, pick ONE unexpected element to anchor the design.
This prevents convergence — it's the memorable thing that makes this design
THIS design, not a generic template.

Good creative seeds:
- An unusual color as the primary (not blue, not purple)
- A distinctive display font that sets the tone
- An unconventional layout technique (asymmetric grid, overlapping elements)
- A signature animation moment (page load choreography, scroll reveal)
- A textural element (noise, grain, mesh gradient, pattern)

Bad creative seeds (overused, will produce generic results):
- Purple-to-blue gradient on white
- Card grid with rounded corners and subtle shadows
- Fade-in-up animations on scroll
- Inter or Space Grotesk as the display font

#### Concrete choices

With the axes scored and creative seed chosen, select:

1. **Typography**: Display font + body font (consult
   `references/frontend-design-guide.md` for sourcing)
2. **Color**: Primary + secondary + accent + neutrals (specific values)
3. **Motion**: Animation philosophy + key moments (load, hover, transitions)
4. **Layout**: Grid system, spacing scale, composition approach
5. **Texture**: Backgrounds, borders, shadows, depth treatment

**Present all choices to the user before proceeding.** Walk through the axis
scores, creative seed, and concrete selections. Do NOT proceed to Phase 3
until the user approves the direction. If the user disagrees, iterate on
the specific choices they reject.

Document all approved choices in the masterPlan before writing code.

#### Failure paths

- If the chosen font is unavailable or has insufficient weights, select
  the next alternative from the same category in the guide.
- If the creative seed produces poor results during implementation, revisit
  it — pick a new seed and adjust the concrete choices before continuing.

### Integration — Design System Extension

When working within an existing system, creativity operates WITHIN the
constraints:

1. **Audit the existing system** — identify its strongest and weakest aspects
2. **Propose 1-2 elevation opportunities** — better animation, more
   intentional spacing, refined typography within the existing type scale
3. **Stay within the token system** — extend it only if the user approves
4. **Match existing patterns** — loading states, error states, component
   structure

The goal is not to redesign the system but to raise the quality bar for the
new work within its vocabulary.

---

## Phase 3: Implementation

### Anti-slop philosophy

Every design decision must be intentional. These patterns signal generic,
unconsidered output — avoid them:

| Category | Avoid | Why |
|---|---|---|
| Fonts | Inter, Roboto, Arial, system-ui as display fonts | Overused in AI output, signals "I didn't choose" |
| Colors | Purple-to-blue gradients on white | The single most common AI aesthetic |
| Layout | Symmetric card grids with uniform shadows | Default template look |
| Animation | Fade-in-up on every element | Overused, creates motion fatigue |
| Patterns | Glassmorphism with no purpose | Trend-following without intention |

This is a summary — the full blacklist with specific alternatives is in
`references/frontend-design-guide.md` § Anti-Slop Blacklist. Always check
the full list.

### Vanilla HTML/CSS

- CSS custom properties for all design tokens
- CSS-only animations (`@keyframes`, `transition`)
- Google Fonts with `font-display: swap` and system font fallbacks
- Semantic HTML (`<header>`, `<nav>`, `<main>`, `<section>`, `<article>`)
- Responsive with CSS Grid/Flexbox and `clamp()` for fluid typography

### React

- CSS modules or styled-components (match project convention)
- Motion library (framer-motion / motion) for orchestrated animations
- Component composition — small, focused components over monoliths
- Font loading with `next/font` (Next.js) or `@fontsource` (other React)
- `prefers-reduced-motion` media query respected in all animations

### Tailwind projects

- Extend `tailwind.config` for custom tokens — don't fight the system
- Custom plugin for unique design tokens when the config is insufficient
- Arbitrary values (`text-[17px]`) only when no token exists
- `@apply` sparingly — prefer utility classes in markup
- Use the project's existing spacing/color patterns; introduce new values
  only with justification

### Font sourcing

Consult `references/frontend-design-guide.md` for the full font sourcing
protocol. Quick reference:

| Source | When | How |
|---|---|---|
| Google Fonts | Default for web | `<link>` tag, `font-display: swap` |
| `@fontsource` | React/Next.js | `npm install @fontsource/font-name` |
| `next/font` | Next.js | Built-in optimization, auto subset |
| Variable fonts | When available | Single file, `font-variation-settings` |
| System fonts | Fallbacks only | Font stack with system-ui |

### Match complexity to vision

Maximalist designs need elaborate code: extensive animations, layered
textures, complex compositions. Minimalist designs need restraint and
precision: careful spacing, typography refinement, subtle details. The
implementation must match the aesthetic — don't write minimal code for a
maximalist vision or bloated code for a minimal one.

---

## Phase 4: Verification

Run the `references/frontend-design-checklist.md` checklist. The key
domains:

**Accessibility:**
- Color contrast passes WCAG AA (4.5:1 text, 3:1 large text)
- Semantic HTML (headings, landmarks, buttons not divs)
- Keyboard navigable with visible focus styles
- `prefers-reduced-motion` respected

**Responsive:**
- Works at 375px (mobile), 768px (tablet), 1280px (desktop)
- No horizontal scroll at any breakpoint
- Touch targets at least 44x44px on mobile
- Typography scales (not just shrinks)

**Performance:**
- Fonts loaded with `font-display: swap` or `optional`
- Animations use `transform` and `opacity` (GPU-composited)
- No excessive DOM depth from decorative wrappers

**Coherence:**
- All colors from defined tokens (no raw hex in components)
- Spacing follows a consistent scale
- Typography uses defined type scale
- Animation timing/easing consistent across elements

### Verification commands

Run the project's own commands first (check `package.json`, `Makefile`,
`CLAUDE.md`). Supplement with:

- **Type check**: `tsc --noEmit` (or project equivalent)
- **Lint**: `eslint`, `biome`, or project linter
- **Accessibility audit**: browser DevTools Accessibility panel, or
  `axe-core` / `@axe-core/cli` if installed
- **Contrast check**: verify specific color pairs meet WCAG AA (4.5:1 body,
  3:1 large text) using browser DevTools or a contrast ratio tool
- **Responsive check**: browser DevTools responsive mode at 375px, 768px,
  1280px

### Failure paths

- If contrast checks fail after implementation, adjust the failing colors
  to meet WCAG AA while staying within the chosen palette's hue — do not
  switch to a completely different palette.
- If the overall result feels generic despite the creative seed, revisit
  the seed and the concrete choices before shipping. The seed should be
  visibly present in the final result.
- If a font fails to load or renders poorly, swap to the next alternative
  from the same category and update the fallback stack.

---

## Acceptance Criteria

- [ ] Design direction presented to user and approved (greenfield mode)
- [ ] All colors from defined tokens — no raw hex in components
- [ ] Accessibility: contrast AA, semantic HTML, keyboard navigation, reduced-motion
- [ ] Responsive at 375px, 768px, 1280px — no horizontal scroll
- [ ] Animations use transform/opacity only
- [ ] No anti-slop patterns present (check full blacklist in guide)
- [ ] Type checker and linter pass
- [ ] Integration mode: side-by-side comparison with existing pages done

---

## Output Contract

This skill produces:

1. **Design decisions** in `discovery.md` or `design.md` (Phase 2) — axis
   scores, creative seed, typography, color, motion, layout, texture choices
2. **Implemented code files** (Phase 3)
3. **Verification results** noted in the masterPlan step's Result field
   (Phase 4) — which checklist items passed, any issues found and resolved

---

## Routing to Other References

| Situation | Read |
|---|---|
| Working within existing design system | `references/ui-consistency-checklist.md` + `references/ui-consistency-guide.md` |
| Adding font/animation dependencies | `references/dependency-checklist.md` |
| User input rendered in UI | `references/security-checklist.md` |
| Testing UI components | `references/testing-checklist.md` |

For the full font sourcing protocol, aesthetic axis deep-dives, animation
patterns, color systems, and the extended anti-slop blacklist, read
`references/frontend-design-guide.md`.
