# Recommended Packages

Packages that the plugin's skills recommend installing in user projects.
These are **not** dependencies of the plugin itself (which is pure
markdown + shell) — they are libraries Claude will suggest when following
skill guidance.

Install globally to have them available in any project, or per-project as
needed.

---

## Color Palette Libraries

### UI Design (referenced by `frontend-design` skill)

| Package | What it does | Install |
|---|---|---|
| `@radix-ui/colors` | 30 curated color scales with built-in light/dark pairs, 12-step functional scale | `npm i @radix-ui/colors` |
| `open-color` | 13 hues × 10 shades, simple and well-balanced | `npm i open-color` |
| `palx` | Single hex → full-spectrum UI palette | `npm i palx` |

### Creative / Immersive (referenced by `immersive-frontend` skill)

| Package | What it does | Install |
|---|---|---|
| `chromotome` | 200+ curated artistic palettes with background + stroke colors | `npm i chromotome` |
| `nice-color-palettes` | 1000 palettes (5 colors each) from ColourLovers | `npm i nice-color-palettes` |
| `riso-colors` | Risograph-inspired flat/textured color set | `npm i riso-colors` |

### Online Tools (no install needed)

| Tool | URL | Use for |
|---|---|---|
| Leonardo (Adobe) | leonardocolor.io | Contrast-ratio-based palette generation |
| tints.dev | tints.dev | Hex → Tailwind 11-shade scale |
| uicolors.app | uicolors.app | Hex → Tailwind shades with visual editor |
| Radix custom palette | radix-ui.com/colors/custom | Brand color → light/dark scale |

---

## Tailwind Integrations

| Package | What it does | Install |
|---|---|---|
| `tailwindcss-radix-colors` | Radix Colors as Tailwind utilities with auto dark mode | `npm i tailwindcss-radix-colors` |

---

## Other Recommended Packages

### Immersive / WebGL (referenced by `immersive-frontend` skill)

| Package | What it does | Install |
|---|---|---|
| `three` | 3D rendering (WebGL) | `npm i three` |
| `gsap` | Animation and scroll-driven effects | `npm i gsap` |
| `lenis` | Smooth scroll synced with rAF | `npm i lenis` |
| `@types/three` | TypeScript types for Three.js | `npm i -D @types/three` |

### Frontend UI (referenced by `frontend-design` skill)

| Package | What it does | Install |
|---|---|---|
| `motion` | React animation (framer-motion successor) | `npm i motion` |

---

## Keeping This File Updated

When a skill recommends a new package, add it here. When a package is
removed from skill guidance, remove it here. The CLAUDE.md rule enforces
this — see `.claude/CLAUDE.md`.
