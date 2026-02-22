---
name: frontend-design
description: "Create distinctive, production-grade frontend interfaces. Detects greenfield vs integration mode, uses a 6-axis decision matrix for aesthetic direction, provides framework-specific implementation guidance, and verifies quality through accessibility, responsive, performance, and coherence checklists. Use when building or designing web components, pages, or applications."
---

# Frontend Design

Build frontend interfaces that are distinctive, intentional, and
production-grade. This skill replaces vague "be creative" advice with a
structured process that produces consistently high-quality results while
preventing the generic aesthetic convergence that plagues AI-generated UIs.

**Announce at start:** "I'm using the frontend-design skill to guide the
design and implementation."

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

Document all choices in the masterPlan before writing code.

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

The deep guide (`references/frontend-design-guide.md`) has an extended
anti-slop blacklist with alternatives.

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
