# Recommended Packages

Packages that the plugin's skills recommend installing in user projects,
plus the plugin's own tool dependencies.

Install globally to have them available in any project, or per-project as
needed.

---

## Plugin Tool Dependencies

These are tools the plugin itself needs to function. They are **not**
project-level npm packages — install them globally.

| Tool | What it does | Install | Required? |
|---|---|---|---|
| `python3` | Core scripting for all hooks and scripts | Pre-installed on macOS/Linux | Yes |
| `git` | Project root detection, version control | Pre-installed on macOS/Linux | Yes |
| `madge` | TypeScript dependency graph analysis | `npm i -g madge` | Only if using dep maps |
| `orbit-mcp` | Plan review and approval via VS Code | `npm i -g orbit-mcp` | Yes (for Orbit review flow) |

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

## Immersive / WebGL (referenced by `immersive-frontend` skill)

| Package | What it does | Install |
|---|---|---|
| `three` | 3D rendering (WebGL) | `npm i three` |
| `@react-three/fiber` | React declarative 3D renderer | `npm i @react-three/fiber` |
| `@react-three/drei` | R3F helpers (Environment, Float, Text, Html, etc.) | `npm i @react-three/drei` |
| `@react-three/postprocessing` | Post-processing effects (Bloom, Vignette, etc.) | `npm i @react-three/postprocessing` |
| `@types/three` | TypeScript types for Three.js | `npm i -D @types/three` |
| `gsap` | Animation and scroll-driven effects | `npm i gsap` |
| `@gsap/react` | GSAP React hooks | `npm i @gsap/react` |
| `lenis` | Smooth scroll synced with rAF | `npm i lenis` |
| `barba.js` | Page transitions for MPA | `npm i @barba/core` |

---

## Frontend UI (referenced by `frontend-design` skill)

| Package | What it does | Install |
|---|---|---|
| `motion` | React animation (framer-motion successor) | `npm i motion` |
| `@fontsource/*` | Self-hosted fonts for React/Next.js/Vite | `npm i @fontsource/<font-name>` |
| `@axe-core/cli` | Accessibility auditing CLI | `npm i -D @axe-core/cli` |

---

## React Native / Mobile (referenced by `react-native-mobile` skill)

### Core Framework

| Package | What it does | Install |
|---|---|---|
| `expo` | Expo SDK 52+ framework | `npx create-expo-app` |
| `expo-router` | File-based routing (v4) | `npx expo install expo-router` |

### Animation & Gestures

| Package | What it does | Install |
|---|---|---|
| `react-native-reanimated` | Worklet-based animations (v4) | `npx expo install react-native-reanimated` |
| `moti` | Declarative Reanimated wrapper | `npm i moti` |
| `react-native-gesture-handler` | Native gesture recognition (v2) | `npx expo install react-native-gesture-handler` |

### Data & State

| Package | What it does | Install |
|---|---|---|
| `zustand` | Client state management | `npm i zustand` |
| `@tanstack/react-query` | Server state / data fetching (v5) | `npm i @tanstack/react-query` |
| `react-native-mmkv` | Fast key-value storage | `npm i react-native-mmkv` |
| `expo-sqlite` | Structured SQL database | `npx expo install expo-sqlite` |

### UI & Platform

| Package | What it does | Install |
|---|---|---|
| `@shopify/flash-list` | Recycled high-performance list | `npm i @shopify/flash-list` |
| `expo-haptics` | Cross-platform haptic feedback | `npx expo install expo-haptics` |
| `expo-symbols` | iOS platform-native icon set | `npx expo install expo-symbols` |
| `expo-blur` | Native blur/vibrancy effects | `npx expo install expo-blur` |
| `@callstack/liquid-glass` | iOS 26 Liquid Glass material | `npm i @callstack/liquid-glass` |
| `@shopify/restyle` | Type-enforced theming (optional) | `npm i @shopify/restyle` |

### Forms & Validation

| Package | What it does | Install |
|---|---|---|
| `react-hook-form` | Performant form handling | `npm i react-hook-form` |
| `zod` | Type-safe validation | `npm i zod` |

---

## Keeping This File Updated

When a skill recommends a new package, add it here. When a package is
removed from skill guidance, remove it here. The CLAUDE.md rule enforces
this — see `.claude/CLAUDE.md`.
