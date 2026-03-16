# Anti-AI-Slop Reference

A shared banlist of patterns that signal generic, unconsidered AI output.
Referenced by creative skills (frontend-design, svg-art, immersive-frontend)
to prevent aesthetic convergence.

**These are defaults, not absolutes.** If the design genuinely calls for one
of these patterns — and you can articulate why — use it. The goal is to
prevent unconscious defaults, not to ban useful techniques.

---

## Typography

Avoid using these as display fonts — they're the first thing every AI reaches
for and immediately signal "AI-generated":

| Banned as display font | Why | Use instead |
|---|---|---|
| Inter | Default on everything, zero personality | Satoshi, General Sans, DM Sans, Outfit |
| Roboto | Android system font, generic | Manrope, Plus Jakarta Sans, Figtree |
| Arial / Helvetica | Safe corporate default | Geist, Switzer, Cabinet Grotesk |
| Open Sans | Overused web default | Source Sans 3, Nunito Sans, Work Sans |
| Space Grotesk | AI-favorite "modern" mono-adjacent | JetBrains Mono, IBM Plex Mono, Fira Code (for actual mono) |
| Poppins as display | Rounded geometric = generic startup | Clash Display, Syne, Instrument Sans |

**Exception:** These fonts are fine for body text when paired with a
distinctive display font. The ban is on using them as the primary visual
identity.

---

## Color

| Pattern | Why it's slop | Do instead |
|---|---|---|
| Purple-to-blue gradient on white | The #1 AI-generated hero pattern | Start from the Temperature axis; derive from brand color |
| Pure black on pure white (`#000` / `#fff`) | Harsh, unrefined, lazy | Near-black on near-white (`#1a1a2e` / `#fafaf9`) or tinted neutrals |
| Generic blue CTA buttons (`#3b82f6`) | Tailwind blue-500 default | Derive CTA color from the design's accent/primary |
| Neon accent on warm brand | Mismatched energy — warm brand looks like a dev tool | Match accent warmth to brand personality |
| Rainbow gradients | Visually chaotic, no brand alignment | 2-3 color gradients from a curated palette |
| Saturated colors on dark without adaptation | Vibrates, poor readability | Desaturate and lighten for dark backgrounds |

---

## Layout

| Pattern | Why it's slop | Do instead |
|---|---|---|
| Symmetric 3-card grid | The most common AI layout — signals zero thought | Bento, masonry, asymmetric splits, varied card sizes |
| Excessive centered layouts | Everything centered = nothing is emphasized | Left-align body text, use asymmetric hero layouts |
| Uniform rounded corners on everything | `rounded-xl` on every element = visual monotony | Vary radius by purpose: sharp for data, rounded for interactive |
| Hero → 3 features → CTA → footer | The template layout every AI defaults to | Break the expected section order, use unexpected compositions |
| Equal-width columns | Grid without hierarchy | Vary column widths (2:1, 3:2 splits), use golden ratio |
| Cards as the only content container | Boxing everything in cards adds visual noise | Use whitespace, typography hierarchy, and subtle dividers |

---

## Animation

| Pattern | Why it's slop | Do instead |
|---|---|---|
| Fade-in-up on every element | Ubiquitous scroll animation = invisible | Animate 2-3 key moments; leave the rest static |
| Glassmorphism with no purpose | Blur + transparency = visual clutter without meaning | Solid surfaces with texture (grain, noise) or accent borders |
| Generic parallax (background moves slower) | Overused, often adds motion sickness | Depth via scale, z-index layering, or scrub-controlled reveals |
| Bounce ease on everything | Playful ≠ bouncy — most brands aren't bouncy | Match easing to brand energy: `power2.out` for calm, `back.out` for playful |
| Loading spinner for everything | Users expect skeleton screens or progressive loading | Skeleton screens, blur-up images, content shimmer |
| Hover scale on every card | Uniform interaction = no hierarchy | Hover only on primary actions; use border/shadow shift for secondary |

---

## Illustration & SVG

| Pattern | Why it's slop | Do instead |
|---|---|---|
| Same-face blob people | The "undraw" aesthetic — generic, interchangeable | Abstract geometric illustrations, or distinctive character design |
| Gradient orbs floating in space | Every AI hero section | Purposeful shapes: topographic lines, data-driven patterns, textured fields |
| Generic tech illustrations | Circuits, nodes, connected dots | Illustrations that relate to the actual product/content |
| Isometric 3D icons | Overused "modern" icon style | Flat icons with personality, or line icons with consistent stroke |
| Decorative circles/dots as filler | Random shapes to fill empty space | Intentional negative space, or patterns that reinforce the design language |

---

## Copy & Microcopy

| Pattern | Why it's slop | Do instead |
|---|---|---|
| "Unlock the power of..." | Generic AI marketing speak | State the specific benefit in plain language |
| "Seamlessly integrate..." | Vague promise, no substance | Describe what actually connects and how |
| "Transform your workflow" | Empty transformation claim | Show the before/after or specific improvement |
| "Built for developers, by developers" | Cliché trust signal | Show actual proof: stats, testimonials, code examples |
| "Get started in minutes" | Unverifiable time claim | Show the actual steps or a demo |
| "Enterprise-grade security" | Meaningless qualifier | Name the specific certifications or practices |
| "Supercharge your..." | Hyperbolic, empty | Describe the specific capability gain |
| "The future of..." | Grandiose, unearned | Focus on present value, not future promises |

---

## How to Use This Reference

1. **During design direction** (Phase 2): check your choices against these
   lists before presenting to the user
2. **During implementation** (Phase 3): scan your output for any patterns
   from these lists
3. **During verification** (Phase 4): final sweep — any slop that crept in?

If you catch yourself reaching for a banned pattern, pause and ask: "Am I
choosing this because it's the right design decision, or because it's the
first thing that comes to mind?" If it's the latter, pick something else.
