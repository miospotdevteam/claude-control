---
name: immersive-frontend
description: "Build award-winning immersive web experiences with WebGL, Three.js, R3F, GSAP ScrollTrigger, custom GLSL shaders, and scroll-driven 3D choreography. Use this skill whenever the user asks for: immersive websites, WebGL experiences, 3D web, creative dev, scroll-driven animations, cinematic scroll, Three.js sites, GSAP + Three.js, motion-driven sites, award-winning website design, Awwwards-quality sites, full-canvas experiences, particle systems, shader effects, smooth scroll with WebGL, preloader animations, image distortion effects, parallax depth, magnetic cursors, text reveal animations, infinite marquees, or any request that goes beyond standard UI into experiential, motion-first, canvas-driven territory. Also use when the user references studios like Active Theory, Lusion, Immersive Garden, or sites from Awwwards/Codrops. Do NOT use for: standard UI components, form-heavy pages, admin dashboards, or layout-focused work without WebGL or advanced motion — use frontend-design instead."
---

# Immersive Frontend

Build full-canvas WebGL experiences with custom shaders, scroll-choreographed
3D scenes, smooth-scrolled cinematics, and theatrical loading sequences. This
skill sits at the intersection of creative coding and web development.

**Announce at start:** "I'm using the immersive-frontend skill to build this
experience."

---

## Prerequisites

This skill operates within the conductor's Step 1-3:

- **Phase 1** (Assessment) runs during Step 1 (Explore).
- **Phase 2** (Architecture) feeds into the masterPlan via `writing-plans`.
- **Phase 3** (Implementation) runs during Step 3 (Execute).
- **Phase 4** (Verification) runs after implementation.

If `brainstorming` ran first and produced visual direction: use those
decisions and skip to Phase 2.

---

## Phase 1: Assessment — What Are We Building?

### Decision Tree

Answer these questions to determine scope and which references to read:

```
Does it need 3D objects / WebGL?
├── YES → Read: references/three-js-patterns.md
│   ├── Custom shaders needed? → Also read: references/shader-recipes.md
│   ├── Scroll drives the 3D scene? → Also read: references/gsap-scroll-patterns.md
│   └── Heavy assets (models, textures)? → Also read: references/architecture.md (preloader)
│
└── NO (2D motion only: text reveals, parallax, marquees)
    └── Read: references/gsap-scroll-patterns.md + references/effects-cookbook.md
```

**Always read:** `references/architecture.md` for the canvas+DOM layering
pattern and smooth scroll setup — these apply to every immersive site.

### Complexity Tiers

| Tier | Description | Stack | Reference Files |
|------|-------------|-------|-----------------|
| **Motion-Enhanced** | Smooth scroll, text reveals, parallax, marquees. No WebGL. | GSAP + Lenis | gsap-scroll-patterns, effects-cookbook |
| **WebGL-Lite** | Canvas background (particles, blobs), DOM content on top. | Three.js + GSAP + Lenis | All except shader-recipes |
| **Full Immersive** | Scroll-driven 3D scenes, custom shaders, preloader, page transitions. | Three.js + GSAP + Lenis + GLSL | All reference files |

---

## Phase 2: Architecture

### Quick-Start Structure (Every Immersive Site)

```
┌─────────────────────────────────────────┐
│  PRELOADER (fixed, z-index: 9999)       │  ← Loads all assets before reveal
│  - Progress counter / bar               │
│  - Theatrical exit animation            │
├─────────────────────────────────────────┤
│  CANVAS LAYER (fixed, z-index: 0)       │  ← Three.js WebGLRenderer
│  - Full viewport, position: fixed       │
│  - Transparent or scene background      │
│  - Renders on GSAP ticker (not own rAF) │
├─────────────────────────────────────────┤
│  DOM CONTENT (relative, z-index: 1)     │  ← Scrollable HTML content
│  - Lenis smooth scroll                  │
│  - ScrollTrigger-driven animations      │
│  - pointer-events: none on overlay text │
├─────────────────────────────────────────┤
│  RENDER LOOP (single GSAP ticker)       │  ← One heartbeat for everything
│  - gsap.ticker.add() drives:            │
│    → Lenis.raf() (smooth scroll)        │
│    → ScrollTrigger.update (animations)  │
│    → renderer.render() (Three.js)       │
│  - gsap.ticker.lagSmoothing(0)          │
└─────────────────────────────────────────┘
```

### The Critical Integration Pattern

```javascript
// ONE render loop to rule them all
const lenis = new Lenis({ duration: 1.2, smoothWheel: true });
lenis.on('scroll', ScrollTrigger.update);

gsap.ticker.add((time) => {
  lenis.raf(time * 1000);        // 1. Smooth scroll
  // ScrollTrigger auto-updates  // 2. Animations
  renderer.render(scene, camera); // 3. WebGL
});

gsap.ticker.lagSmoothing(0); // Prevent desync after lag spikes
```

### Technology Selection Guide

| Need | Use | Why |
|------|-----|-----|
| 3D objects, models, particles | **Three.js** (vanilla) | Full control, smaller bundle |
| 3D in React app | **React Three Fiber + Drei** | Declarative, auto-disposal, hooks |
| Scroll-linked animations | **GSAP ScrollTrigger** | Scrub, pin, snap, batch, timeline |
| Smooth scrolling | **Lenis** | Syncs with rAF, works with ScrollTrigger |
| Text split/reveal | **GSAP SplitText** (or manual split) | Industry standard for char/word/line animation |
| Page transitions (MPA) | **Barba.js** | Preserves canvas across navigations |
| Spring physics (React) | **Motion (Framer Motion)** | AnimatePresence, layout animations |
| Custom visual effects | **GLSL shaders** | GPU-accelerated, per-pixel control |
| 2D parallax only | **GSAP ScrollTrigger alone** | No WebGL overhead needed |

### CDN Links (for single-file HTML)

```html
<!-- Three.js -->
<script src="https://cdn.jsdelivr.net/npm/three@0.152.0/build/three.min.js"></script>

<!-- GSAP + Plugins -->
<script src="https://cdnjs.cloudflare.com/ajax/libs/gsap/3.12.5/gsap.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/gsap/3.12.5/ScrollTrigger.min.js"></script>

<!-- Lenis Smooth Scroll -->
<script src="https://cdn.jsdelivr.net/npm/lenis@1.1.18/dist/lenis.min.js"></script>
```

---

## Phase 3: Implementation Rules

### Critical Performance Rules

1. **One render loop.** Drive Lenis, ScrollTrigger, and Three.js from
   `gsap.ticker.add()`. Never use a separate `requestAnimationFrame`.

2. **Cap pixel ratio at 2.** `Math.min(window.devicePixelRatio, 2)`.
   3x DPR triples GPU work for imperceptible gain.

3. **Animate only transform and opacity** in DOM. These are GPU-composited.
   Never animate `width`, `height`, `top`, `left`, `margin`, `padding`.

4. **Dispose everything.** GPU memory is NOT garbage collected. Call
   `.dispose()` on geometries, materials, and textures when removing objects.

5. **Preload before reveal.** Gate the experience behind a loading screen.
   Use `THREE.LoadingManager` for 3D assets, `Promise.all` for others.

6. **scrub: 0.5 to 1.5** for scroll-driven animations. Raw `scrub: true`
   feels jerky. The smoothing value adds polish.

7. **Draw calls < 50 mobile, < 100 desktop.** Monitor with
   `renderer.info.render.calls`. Use InstancedMesh for repeated geometry.

8. **Use autoAlpha over opacity** in GSAP. It sets `visibility: hidden`
   at 0, removing the element from the render tree.

9. **Texture sizes:** Max 2048x2048 for hero, 1024x1024 for gallery,
   512x512 for UI. Power-of-two dimensions for GPU efficiency.

10. **Mobile fallback.** Detect via `matchMedia` and serve reduced
    particle counts, no shadows, simpler shaders, lower DPR.

### Anti-Patterns — What NOT to Do

| Anti-Pattern | Why It Fails | Do This Instead |
|---|---|---|
| Separate rAF for Lenis and Three.js | Frame desync, tearing between DOM and canvas | Single gsap.ticker drives everything |
| `scrub: true` (no smoothing) | Jerky, mechanical camera/animation movement | `scrub: 0.5` to `scrub: 2` |
| Skipping the preloader | White flash, pop-in, broken first impression | Always gate behind a loading screen |
| Animating `top`/`left`/`width` | Triggers layout reflow every frame, kills FPS | Use `transform` (x, y, scale, rotation) |
| `devicePixelRatio` uncapped | GPU meltdown on 3x Retina, >4x fill rate | `Math.min(window.devicePixelRatio, 2)` |
| Forgetting `.dispose()` | GPU memory leak, crashes after page transitions | Dispose geometry, material, textures on cleanup |
| `any` type on Three.js objects | Loses intellisense, hides bugs | Proper typing or let inference work |
| Huge textures (4K+) | GPU memory explosion, slow load | 2048 max, use KTX2 compression |
| Raw `window.scrollY` in render loop | Desyncs with Lenis smooth scroll | Read `lenis.scroll` or `lenis.progress` |
| No resize handler | Broken aspect ratio, stretched canvas | Update camera.aspect, renderer.setSize, ScrollTrigger.refresh() |
| Inline shaders as template literals without `/* glsl */` | No syntax highlighting, hard to debug | Tag with `/* glsl */` or use `<script type="x-shader">` |
| Post-processing > 6 passes | Each pass is a full-screen draw, kills mobile | Combine effects, keep to 3-5 passes |

### Shader Integration Pattern

When using custom shaders, always provide uniforms for time, scroll, and mouse:

```javascript
const material = new THREE.ShaderMaterial({
  uniforms: {
    uTime:           { value: 0 },
    uScrollProgress: { value: 0 },      // 0-1, full page
    uScrollVelocity: { value: 0 },      // Lenis velocity
    uMouse:          { value: new THREE.Vector2(0.5, 0.5) },
    uResolution:     { value: new THREE.Vector2(width, height) },
  },
  vertexShader: vertexShaderCode,
  fragmentShader: fragmentShaderCode,
});

// Update in the single ticker
gsap.ticker.add((time) => {
  material.uniforms.uTime.value = time;
  material.uniforms.uScrollProgress.value = lenis.progress;
  material.uniforms.uScrollVelocity.value = lenis.velocity;
});
```

### Responsive WebGL Pattern

```javascript
function onResize() {
  const w = window.innerWidth;
  const h = window.innerHeight;

  camera.aspect = w / h;
  camera.updateProjectionMatrix();
  renderer.setSize(w, h);
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));

  // Update resolution uniform if using shaders
  material.uniforms.uResolution.value.set(
    w * renderer.getPixelRatio(),
    h * renderer.getPixelRatio()
  );

  // Recalculate ScrollTrigger positions
  ScrollTrigger.refresh();
}
window.addEventListener('resize', onResize);
```

---

## Phase 4: Verification

### Immersive-Specific Checklist

- [ ] **60fps**: No frame drops during scroll (check DevTools Performance)
- [ ] **Preloader**: All assets load before experience reveals
- [ ] **Smooth scroll**: Lenis + ScrollTrigger synced via GSAP ticker
- [ ] **Responsive**: Canvas resizes, camera updates, ScrollTrigger refreshes
- [ ] **Disposal**: All geometries/materials/textures disposed on cleanup
- [ ] **DPR capped**: `Math.min(devicePixelRatio, 2)` applied
- [ ] **Mobile**: Reduced quality tier applied (fewer particles, no shadows)
- [ ] **No layout animation**: Only transform/opacity animated in DOM
- [ ] **Draw calls**: Within budget (check `renderer.info.render.calls`)
- [ ] **Scroll feels right**: `scrub` has smoothing value, not raw `true`

### Standard Checks (from engineering-discipline)

- [ ] Type checker passes
- [ ] Linter passes
- [ ] No `any` / `as any` in TypeScript
- [ ] prefers-reduced-motion respected (disable WebGL motion, simplify DOM animation)

---

## Reference Files

| File | Contents | When to Read |
|------|----------|--------------|
| `references/three-js-patterns.md` | Scene setup, cameras, materials, R3F, particles, post-processing, disposal | Any WebGL work |
| `references/gsap-scroll-patterns.md` | GSAP core, ScrollTrigger, Lenis, SplitText, Motion, timelines | Any scroll-driven animation |
| `references/shader-recipes.md` | Complete GLSL: noise displacement, chromatic aberration, distortion, grain, ripple, vignette, fresnel | Custom shader effects |
| `references/architecture.md` | Preloader, canvas+DOM layering, DOM-to-WebGL sync, page transitions, performance budgets | Site architecture decisions |
| `references/effects-cookbook.md` | 8 complete implementations: preloader, smooth scroll, text reveal, marquee, magnetic cursor, image distortion, parallax, camera path | Building specific effects |

### Routing to Other Skills

| Need | Skill |
|------|-------|
| Standard UI/UX design decisions | `frontend-design` |
| Creative direction brainstorming | `brainstorming` |
| Implementation planning | `writing-plans` |
| Testing strategy | `test-driven-development` |

---

## Output Contract

This skill produces:

1. **Architecture decisions** in `discovery.md` — tier selection, tech stack,
   performance budget, mobile strategy
2. **Working code** — HTML/CSS/JS with WebGL, shaders, scroll animations
3. **Verification results** in masterPlan step Results — fps, draw calls,
   disposal confirmed, responsive confirmed
