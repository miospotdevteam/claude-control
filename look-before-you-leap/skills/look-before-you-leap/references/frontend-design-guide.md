# Frontend Design Guide

Comprehensive reference for building distinctive, high-quality frontend
interfaces. This guide provides concrete, actionable guidance — not philosophy.
Use it alongside the `frontend-design-checklist.md` and the main
`frontend-design` skill.

---

## Aesthetic Axes Deep Dive

The 6-axis decision matrix from the skill narrows the aesthetic space. Here's
how each axis maps to concrete design choices.

### Audience (Technical ←→ General Public)

| Score | Typography | Color | Layout |
|---|---|---|---|
| 1-2 (Technical) | Monospace accents, high x-height body, code-like elements | Muted palette, dark mode friendly, terminal greens/ambers | Dense, information-rich, sidebar navigation |
| 3 (Mixed) | Clean sans-serif, clear hierarchy | Balanced palette with good contrast | Standard grid, clear sections |
| 4-5 (General) | Friendly display fonts, generous sizing | Vibrant, approachable colors | Spacious, visual-first, clear CTAs |

### Formality (Corporate ←→ Casual)

| Score | Typography | Color | Texture |
|---|---|---|---|
| 1-2 (Corporate) | Serif or restrained sans, traditional hierarchy | Conservative palette, navy/charcoal/white | Clean surfaces, structured grids |
| 3 (Balanced) | Modern sans-serif, moderate personality | Professional with one accent | Light textures, balanced whitespace |
| 4-5 (Casual) | Display fonts with personality, loose hierarchy | Bold colors, playful combinations | Organic shapes, hand-drawn elements, patterns |

### Energy (Calm ←→ Dynamic)

| Score | Animation | Layout | Color |
|---|---|---|---|
| 1-2 (Calm) | Subtle transitions, no entrance animations | Stable grid, predictable flow | Muted, low-saturation |
| 3 (Moderate) | Purposeful hover states, gentle page transitions | Some variation, deliberate emphasis | Moderate saturation with clear hierarchy |
| 4-5 (Dynamic) | Choreographed entrances, scroll-triggered effects, hover surprises | Asymmetric, overlapping, diagonal flow | High saturation, strong contrasts |

### Density (Spacious ←→ Dense)

| Score | Spacing | Typography | Components |
|---|---|---|---|
| 1-2 (Spacious) | Generous margins and padding, large gaps | Large type scale, wide line-height | Few elements per viewport, hero sections |
| 3 (Balanced) | Standard spacing scale, clear breathing room | Medium type scale, 1.5-1.6 line-height | Comfortable density, clear grouping |
| 4-5 (Dense) | Compact spacing, efficient use of space | Smaller body text, tighter line-height | Tables, dashboards, multi-column layouts |

### Era (Classic ←→ Contemporary)

| Score | Typography | Patterns | Color |
|---|---|---|---|
| 1-2 (Classic) | Serif fonts, traditional pairings | Proven layouts, standard components | Timeless palettes, earth tones |
| 3 (Modern) | Contemporary sans-serif, clean lines | Current best practices | Clean, well-established combinations |
| 4-5 (Trendy) | Variable fonts, experimental display types | Glassmorphism, bento grids, scroll-driven animations | Current trend palettes (but make them yours) |

### Temperature (Warm ←→ Cool)

| Score | Shapes | Typography | Color |
|---|---|---|---|
| 1-2 (Warm) | Rounded corners, organic curves, soft edges | Humanist sans-serif, rounded letterforms | Warm neutrals, oranges, yellows, earth tones |
| 3 (Neutral) | Moderate rounding, balanced geometry | Neutral sans-serif | Balanced palette, blue-grays |
| 4-5 (Cool) | Sharp corners, geometric forms, precise lines | Geometric sans-serif, monospace | Cool grays, blues, teals, stark whites |

---

## Font Sourcing Protocol

### Where to get fonts

| Source | When to use | How to load | Pros | Cons |
|---|---|---|---|---|
| Google Fonts | Default for any web project | `<link>` tag or `@import`, always set `font-display: swap` | Free, CDN-cached, huge library | Everyone uses the top 20 |
| `@fontsource` | React, Next.js, Vite projects | `npm install @fontsource-variable/font-name` or `@fontsource/font-name` | Self-hosted, tree-shakeable, no external requests | Must install per font |
| `next/font` | Next.js specifically | `import { FontName } from 'next/font/google'` | Auto-optimized, subset, zero layout shift | Next.js only |
| Variable fonts | When a font offers a variable version | Single file, use `font-variation-settings` or `font-weight` ranges | One file replaces 5+, fine control over weight/width | Not all fonts available |
| System fonts | Fallback stack only | `system-ui, -apple-system, sans-serif` | Zero load time | No distinctiveness |

### Font selection process

1. **From the axes**: determine the typography character needed (geometric,
   humanist, slab, monospace, display, etc.)
2. **Browse with intent**: filter Google Fonts by category, sort by
   "trending" or "date added" to find less common options
3. **Test the pairing**: display font for headings (h1-h3), body font for
   text. Verify contrast in weight and character between the two
4. **Anti-overuse check**: is this font in the overused list below? If yes,
   pick another — there are hundreds of good options
5. **Verify metrics**: check that the font has the weights you need (at
   minimum: regular 400, medium 500 or semibold 600, bold 700)
6. **Set fallbacks**: choose a system font with similar metrics to minimize
   layout shift during loading

### Fallback font stacks

```css
/* Geometric sans */
font-family: 'Your Font', 'Helvetica Neue', Arial, sans-serif;

/* Humanist sans */
font-family: 'Your Font', 'Gill Sans', Calibri, sans-serif;

/* Monospace */
font-family: 'Your Mono', 'SF Mono', 'Cascadia Code', 'Fira Code', monospace;

/* Serif */
font-family: 'Your Serif', Georgia, 'Times New Roman', serif;

/* Display (varies) */
font-family: 'Your Display', Impact, 'Arial Black', sans-serif;
```

---

## Animation Patterns

### By framework

**Vanilla CSS:**
```css
/* Entrance animation */
@keyframes slide-up {
  from { opacity: 0; transform: translateY(20px); }
  to { opacity: 1; transform: translateY(0); }
}
.animate-in {
  animation: slide-up 0.5s ease-out forwards;
}

/* Hover interaction */
.card {
  transition: transform 0.2s ease, box-shadow 0.2s ease;
}
.card:hover {
  transform: translateY(-4px);
  box-shadow: 0 12px 24px rgba(0,0,0,0.1);
}

/* Reduced motion */
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    transition-duration: 0.01ms !important;
  }
}
```

**React with framer-motion / motion:**
```jsx
import { motion } from 'framer-motion';

// Staggered entrance
<motion.div
  initial={{ opacity: 0, y: 20 }}
  animate={{ opacity: 1, y: 0 }}
  transition={{ duration: 0.5, delay: index * 0.1 }}
>
  {content}
</motion.div>

// Layout animation
<motion.div layout transition={{ type: 'spring', stiffness: 300 }}>
  {/* content that changes size/position */}
</motion.div>
```

**Tailwind with utilities:**
```html
<!-- Transition -->
<div class="transition-all duration-300 ease-out hover:-translate-y-1 hover:shadow-lg">

<!-- Animation (define in tailwind.config) -->
<div class="animate-fade-in">
```

### High-impact animation moments

Prioritize these over scattered micro-interactions:

1. **Page load choreography** — staggered reveals with `animation-delay`,
   hero content first, then supporting elements
2. **Scroll-triggered reveals** — content appearing as user scrolls, using
   `IntersectionObserver` or CSS `animation-timeline`
3. **State transitions** — loading to loaded, collapsed to expanded, tab
   switching with smooth content transitions
4. **Hover depth** — cards that lift, buttons that compress, links that
   underline with animated width

### Animation principles

- Use `transform` and `opacity` only — these are GPU-composited and won't
  trigger layout recalculations
- Consistent easing: pick one curve and use it throughout (e.g.,
  `cubic-bezier(0.4, 0, 0.2, 1)`)
- Consistent duration scale: fast (150ms) for micro-interactions, medium
  (300ms) for state changes, slow (500ms+) for choreographed entrances
- Always respect `prefers-reduced-motion`

### Micro-interaction pattern library

Complete recipes for common interactive elements:

**Focus ring (keyboard-only):**
```css
/* Only show on keyboard navigation, not mouse clicks */
:focus-visible {
  outline: none;
  box-shadow: 0 0 0 2px var(--surface-0), 0 0 0 4px var(--ring);
}
```

**Toggle switch:**
```css
.toggle {
  width: 44px; height: 24px;
  background: var(--muted);
  border-radius: 9999px;
  transition: background 200ms ease;
  position: relative;
}
.toggle[aria-checked="true"] { background: var(--primary); }
.toggle::after {
  content: '';
  width: 20px; height: 20px;
  border-radius: 50%;
  background: white;
  position: absolute; top: 2px; left: 2px;
  transition: transform 200ms ease;
}
.toggle[aria-checked="true"]::after { transform: translateX(20px); }
```

**Dropdown / menu open:**
```css
.dropdown-menu {
  transform-origin: top;
  transform: scaleY(0);
  opacity: 0;
  transition: transform 150ms ease-out, opacity 100ms ease-out;
}
.dropdown-menu[data-open] {
  transform: scaleY(1);
  opacity: 1;
}
```

**Animated underline link:**
```css
.link {
  background-image: linear-gradient(currentColor, currentColor);
  background-size: 0% 2px;
  background-position: left bottom;
  background-repeat: no-repeat;
  transition: background-size 250ms ease-out;
}
.link:hover { background-size: 100% 2px; }
```

**Button press feedback:**
```css
.btn { transition: transform 100ms ease; }
.btn:active { transform: scale(0.97); }
```

**Card hover with border glow:**
```css
.card {
  border: 1px solid var(--border);
  transition: border-color 200ms ease, box-shadow 200ms ease;
}
.card:hover {
  border-color: var(--primary);
  box-shadow: 0 0 0 1px var(--primary);
}
```

**Reduced motion override** — wrap ALL micro-interactions:
```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    transition-duration: 0.01ms !important;
    animation-duration: 0.01ms !important;
  }
}
```

---

## Color System

### Pre-built palette libraries (recommended first)

Before generating colors from scratch, consider using a pre-curated system.
These are expert-designed, accessibility-tested, and avoid color clashes:

| Library | Best for | Install |
|---|---|---|
| **Radix Colors** (`@radix-ui/colors`) | Projects with dark mode — 12-step functional scales with built-in light/dark pairs. Each step has a specific purpose (bg, subtle bg, border, text, etc.) | `npm i @radix-ui/colors` |
| **Open Color** (`open-color`) | Simple projects — 13 hues × 10 shades, clean and balanced | `npm i open-color` |
| **Palx** (`palx`) | Brand color expansion — one hex in, full-spectrum palette out | `npm i palx` |
| **Tailwind v4 built-in** | Already using Tailwind — OKLCH palette, wide gamut | Built-in |

**When to use pre-built vs generate:**
- **Use pre-built** when you need a reliable, accessible palette quickly, or
  when dark mode support matters (Radix is excellent for this)
- **Generate from brand color** when the project has a specific brand hex
  that must anchor the palette (use Palx, tints.dev, or the methods below)
- **Use Tailwind built-in** when the project already uses Tailwind and the
  default palette fits the design direction

For Tailwind projects, `tailwindcss-radix-colors` brings Radix's functional
scales into Tailwind utilities with automatic dark mode.

See `PACKAGES.md` in the plugin root for the full list of recommended
packages and online tools.

### Building a palette from the axes

1. **Choose a primary** based on Temperature + Energy:
   - Warm + Calm → muted earth tones, terracotta, sage
   - Warm + Energetic → vibrant orange, coral, gold
   - Cool + Calm → steel blue, slate, muted teal
   - Cool + Energetic → electric blue, cyan, vivid green

2. **Choose neutrals** based on Temperature:
   - Warm → warm grays (hint of brown/yellow): `#1a1a17`, `#2d2d28`, `#f5f3f0`
   - Cool → cool grays (hint of blue): `#0f1117`, `#1e2028`, `#f0f2f5`

3. **Choose an accent** — this should complement, not match, the primary:
   - Complementary: opposite on the color wheel
   - Analogous: adjacent on the color wheel but more saturated
   - The creative seed can BE the accent color

4. **Define the full scale**: for each color, generate a 50-950 scale (or
   at minimum: light, default, dark variants)

### Palette Generation Methods

Given a brand color, generate a full system:

**Method 1: HSL Shift** (simplest, good for most projects)
1. Convert the brand hex to HSL
2. Hold hue constant; vary saturation and lightness:
   - 50 (lightest): S -40%, L 95%
   - 100: S -30%, L 90%
   - 200: S -20%, L 80%
   - ...ramp down to...
   - 900 (darkest): S +5%, L 15%
   - 950: S +10%, L 8%
3. The 500 shade should be close to the original brand color

**Method 2: OKLCH** (perceptually uniform — better for dark mode)
1. Convert the brand hex to OKLCH (`oklch(L C H)`)
2. Hold hue (H) constant; vary lightness (L) and chroma (C):
   - Light shades: high L (0.90-0.97), reduce C slightly
   - Dark shades: low L (0.15-0.30), reduce C to avoid muddy saturation
3. OKLCH produces more visually consistent steps than HSL because it
   models human perception

**Method 3: Complementary / Split-Complementary** (for secondary + accent)
1. Primary hue established from brand color
2. Secondary: rotate hue 180° (complementary) or ±150° (split-complementary)
3. Accent: rotate hue 30-60° from primary (analogous but more saturated)
4. Generate each color's 50-950 scale using Method 1 or 2

**Neutral generation:** Tint neutrals toward the primary hue for cohesion:
```css
/* Warm neutrals (primary is warm) */
--neutral-50: oklch(0.97 0.005 80);
--neutral-900: oklch(0.15 0.01 80);

/* Cool neutrals (primary is cool) */
--neutral-50: oklch(0.97 0.005 250);
--neutral-900: oklch(0.15 0.01 250);
```

### Dark Mode Color Adaptation

When adapting a light-theme palette for dark mode:

1. **Backgrounds**: Don't use pure black. Use the darkest neutral with a
   subtle hue tint: `oklch(0.13 0.01 <hue>)` for base,
   `oklch(0.16 0.01 <hue>)` for surface-1, `oklch(0.19 0.01 <hue>)` for
   surface-2. Higher elevation = lighter.

2. **Text**: Reduce contrast slightly. Use `oklch(0.90 0.005 <hue>)` for
   body text instead of pure white. This reduces eye strain.

3. **Primary color**: The 500 shade used in light mode often needs to shift
   to 400 or 300 in dark mode for sufficient contrast against dark
   backgrounds. Test the pair: `primary-on-surface` must meet 4.5:1.

4. **Borders and dividers**: Use `oklch(0.25 0.01 <hue>)` — visible but
   subtle. Light mode borders (usually gray-200) don't translate directly.

5. **Shadows**: Darker and more diffuse. Shadows on dark surfaces are
   nearly invisible at light-mode opacity — increase opacity by 2-3x or
   use a colored shadow (subtle primary glow) for elevation cues.

6. **Semantic tokens** that adapt:
```css
:root {
  --surface-0: oklch(0.98 0.005 250);
  --surface-1: oklch(0.96 0.005 250);
  --on-surface: oklch(0.15 0.02 250);
  --border: oklch(0.88 0.01 250);
}
.dark {
  --surface-0: oklch(0.13 0.01 250);
  --surface-1: oklch(0.17 0.01 250);
  --on-surface: oklch(0.90 0.005 250);
  --border: oklch(0.25 0.01 250);
}
```

### Accessibility-first color rules

- Body text on background: minimum 4.5:1 contrast ratio
- Large text (18px+ or 14px+ bold): minimum 3:1 contrast ratio
- UI elements (borders, icons): minimum 3:1 against background
- Don't rely on color alone to convey information — add icons, patterns,
  or text labels

---

## Layout Composition

### Breaking the grid (intentionally)

Standard grid layouts feel templated. Intentional breaks create visual
interest:

- **Asymmetric two-column**: 60/40 or 70/30 splits instead of 50/50
- **Overlapping elements**: images that bleed into adjacent sections,
  text that overlaps a background change
- **Varied section heights**: not every section needs to be viewport height
- **Diagonal flow**: angled section dividers, rotated background elements
- **Negative space as design element**: leaving areas intentionally empty
  to create tension and focus

### Spacing scale

Pick a base unit and build a scale. Common approaches:

```
4px base:  4, 8, 12, 16, 24, 32, 48, 64, 96, 128
8px base:  8, 16, 24, 32, 48, 64, 96, 128, 192
Tailwind:  1(4px), 2(8px), 3(12px), 4(16px), 6(24px), 8(32px), 12(48px), 16(64px)
```

Use the scale consistently. If your spacing is 16px between elements,
don't randomly use 18px somewhere — it breaks the rhythm even if the user
can't articulate why.

---

## Anti-Slop Blacklist

These choices appear so frequently in AI-generated frontends that using them
signals "undesigned." Avoid them unless you have a specific, contextual
reason.

### Overused fonts

| Font | Problem | Alternatives |
|---|---|---|
| Inter | Default for everything | Satoshi, General Sans, Switzer, Plus Jakarta Sans |
| Space Grotesk | AI-generated default | Outfit, Syne, Cabinet Grotesk, Familjen Grotesk |
| Roboto | Android default, everywhere | Source Sans 3, Nunito Sans, Figtree |
| Poppins | Overused geometric | DM Sans, Red Hat Display, Urbanist |
| Montserrat | Overused geometric | Manrope, Clash Display, Epilogue |
| Open Sans | Safe but generic | Lato, Noto Sans, Atkinson Hyperlegible |

### Overused color patterns

| Pattern | Alternative approach |
|---|---|
| Purple-to-blue gradient on white | Start from the Temperature axis — what color does the CONTENT need? |
| Black text on pure white (#000 on #fff) | Use near-black on near-white for less harsh contrast (`#1a1a2e` on `#fafaf9`) |
| Gradient background behind cards | Solid color with texture (noise, grain) or a single distinctive accent |
| Blue primary (#3B82F6 / Tailwind blue-500) | Pick a primary from the project's actual identity |

### Overused layout patterns

| Pattern | Alternative approach |
|---|---|
| 3-column card grid with identical shadows | Vary card sizes, use a masonry or bento layout, or single-column with emphasis |
| Hero with centered text + gradient bg | Asymmetric hero, split layout, editorial-style with large typography |
| Features section with icon + title + description grid | Storytelling layout, numbered steps, before/after comparisons |
| Footer with 4 equal columns | Asymmetric footer, minimal single-line, or magazine-style |

### Overused animation patterns

| Pattern | Alternative approach |
|---|---|
| Fade-in-up on every scroll section | Be selective — animate only 2-3 key moments per page |
| Slow float/pulse on decorative elements | Use subtle `transform: scale` on hover instead of ambient motion |
| Typing animation on hero text | Choreographed entrance with staggered word reveals |
| Parallax scrolling on everything | Use parallax on ONE hero element, keep the rest stable |

---

## Framework-Specific Patterns

### Single HTML file delivery

When the output is a single `.html` file:

- Inline CSS in a `<style>` block — no external stylesheets to load
- Google Fonts via `<link>` in `<head>` with `&display=swap`
- CSS custom properties for all tokens in `:root`
- Responsive with CSS Grid, `clamp()`, and `@media` queries
- JavaScript in a `<script>` block at the end of `<body>` (if needed)

### Next.js / React app

- Fonts via `next/font` (zero layout shift) or `@fontsource`
- CSS modules for component styles, or Tailwind with config extensions
- Motion via `framer-motion` / `motion` for orchestrated animations
- Image optimization via `next/image` or framework equivalent
- Server components where possible to reduce client bundle

### Tailwind project

- Extend `theme` in `tailwind.config` for custom values — avoid fighting
  the defaults
- Create semantic class names via Tailwind plugins for repeated patterns
- Use `@layer components` for component-level custom utilities
- Arbitrary values (`[17px]`) only when truly one-off
- Check for existing Tailwind plugins: `@tailwindcss/typography`,
  `@tailwindcss/forms`, `@tailwindcss/container-queries`
