# Architecture Patterns

Preloader, canvas+DOM layering, DOM-to-WebGL sync, scroll-driven 3D
choreography, smooth scroll integration, page transitions, responsive
WebGL, and performance budgets.

---

## 1. The Preloader Pattern

Gate the experience behind a loading screen. No pop-in, no white flashes.

### Asset Loader (THREE.LoadingManager)

```javascript
class AssetLoader {
  constructor() {
    this.manager = new THREE.LoadingManager();
    this.items = {};

    this.manager.onLoad = () => this.onAllLoaded();
    this.manager.onProgress = (url, loaded, total) => {
      this.onProgress(loaded / total);
    };

    this.textureLoader = new THREE.TextureLoader(this.manager);
    this.gltfLoader = new GLTFLoader(this.manager);
  }

  onProgress(progress) {} // Override
  onAllLoaded() {}        // Override

  loadTexture(name, url) {
    this.textureLoader.load(url, (tex) => { this.items[name] = tex; });
  }

  loadModel(name, url) {
    this.gltfLoader.load(url, (gltf) => { this.items[name] = gltf; });
  }

  get(name) { return this.items[name]; }
}
```

### Promise-Based Loading

```javascript
// loadAsync is built into Three.js loaders (r147+)
const [tex1, tex2, model] = await Promise.all([
  textureLoader.loadAsync('/textures/hero.jpg'),
  textureLoader.loadAsync('/textures/noise.png'),
  gltfLoader.loadAsync('/models/scene.glb'),
]);
```

### Preloader UI

```html
<div id="preloader" style="position:fixed; inset:0; z-index:9999; background:#0a0a0a;">
  <div class="counter" style="font-variant-numeric:tabular-nums;">0</div>
  <div class="progress-bar"><div class="fill" style="width:0%"></div></div>
</div>
```

```javascript
// Smooth the counter with GSAP (avoids jumpy numbers)
const state = { progress: 0 };
assetLoader.onProgress = (p) => {
  gsap.to(state, {
    progress: p * 100,
    duration: 0.4,
    onUpdate: () => {
      counter.textContent = Math.round(state.progress);
      fill.style.width = Math.round(state.progress) + '%';
    }
  });
};
```

### Theatrical Reveal

```javascript
function revealSite() {
  const tl = gsap.timeline({
    onComplete: () => {
      document.getElementById('preloader').remove();
      document.body.style.overflow = '';
    }
  });

  tl.to('.counter', { scale: 1.2, opacity: 0, duration: 0.5, ease: 'power3.in' })
    .to('.progress-bar', { opacity: 0, duration: 0.3 }, '<')
    .to('#preloader', { clipPath: 'inset(0 0 100% 0)', duration: 0.8, ease: 'power4.inOut' });
}
```

**Rules:**
- `font-variant-numeric: tabular-nums` prevents layout shift as digits change
- Remove the preloader DOM node after exit animation to free memory
- `overflow: hidden` on body during load, restored after reveal
- The render loop does NOT start until preloader fires `onComplete`

---

## 2. Canvas + DOM Layering

### The Three-Layer Sandwich

```html
<body>
  <!-- Layer 0: WebGL (fixed, behind everything) -->
  <canvas id="webgl" style="position:fixed; inset:0; z-index:0;"></canvas>

  <!-- Layer 1: Scrollable DOM content -->
  <main id="smooth-wrapper" style="position:relative; z-index:1;">
    <div id="smooth-content">
      <section class="hero">
        <h1 style="pointer-events:none; mix-blend-mode:difference;">Title</h1>
      </section>
      <section class="gallery">
        <div class="gallery-item" data-webgl-media>
          <img src="image.jpg" alt="" />
        </div>
      </section>
    </div>
  </main>

  <!-- Layer 2: Fixed UI (nav, cursor) -->
  <nav style="position:fixed; top:0; z-index:100;">...</nav>
</body>
```

**Key CSS rules:**
- Canvas: `position: fixed` fills viewport, sits behind DOM
- Overlay text: `pointer-events: none` + `mix-blend-mode: difference`
- Interactive elements on top need explicit `pointer-events: auto`

---

## 3. DOM-to-WebGL Sync

Sync Three.js planes with DOM element positions. The DOM is the truth;
WebGL follows.

### Pixel-to-World-Unit Conversion

```javascript
function getViewSizeAtDepth(camera, depth = 0) {
  const fovRad = (camera.fov * Math.PI) / 180;
  const distance = camera.position.z - depth;
  const height = 2 * Math.tan(fovRad / 2) * distance;
  const width = height * camera.aspect;
  return { width, height };
}
```

### WebGL Media Class

```javascript
class WebGLMedia {
  constructor({ element, scene, camera, viewport, screen }) {
    this.element = element;
    this.viewport = viewport; // { width, height } in world units
    this.screen = screen;     // { width, height } in pixels

    this.geometry = new THREE.PlaneGeometry(1, 1, 20, 20);
    this.material = new THREE.ShaderMaterial({ /* ... */ });
    this.mesh = new THREE.Mesh(this.geometry, this.material);
    scene.add(this.mesh);
  }

  updateBounds() {
    const rect = this.element.getBoundingClientRect();
    this.bounds = { top: rect.top, left: rect.left, width: rect.width, height: rect.height };
  }

  updateScale() {
    this.mesh.scale.x = (this.bounds.width / this.screen.width) * this.viewport.width;
    this.mesh.scale.y = (this.bounds.height / this.screen.height) * this.viewport.height;
  }

  updatePosition(scrollY = 0) {
    this.mesh.position.x =
      ((this.bounds.left + this.bounds.width / 2) / this.screen.width)
      * this.viewport.width - this.viewport.width / 2;

    this.mesh.position.y =
      -((this.bounds.top + this.bounds.height / 2 - scrollY) / this.screen.height)
      * this.viewport.height + this.viewport.height / 2;
  }

  update(scrollY, time) {
    this.updatePosition(scrollY);
    this.material.uniforms.uTime.value = time;
  }

  destroy() {
    this.mesh.parent.remove(this.mesh);
    this.geometry.dispose();
    this.material.dispose();
  }
}
```

---

## 4. Scroll-Driven 3D Choreography

### Camera Dolly Along a Path

```javascript
const cameraPath = new THREE.CatmullRomCurve3([
  new THREE.Vector3(0, 2, 10),
  new THREE.Vector3(8, 3, 6),
  new THREE.Vector3(10, 0, 0),
  new THREE.Vector3(0, -2, -10),
  new THREE.Vector3(-8, 2, -5),
], true); // true = closed loop

ScrollTrigger.create({
  trigger: '#experience',
  start: 'top top',
  end: 'bottom bottom',
  scrub: 2,
  onUpdate: (self) => {
    const pos = cameraPath.getPointAt(self.progress);
    camera.position.copy(pos);
    lookAtTarget.lerp(new THREE.Vector3(0, 0, 0), 0.1);
    camera.lookAt(lookAtTarget);
    renderer.render(scene, camera);
  },
});
```

**Use `getPointAt()` (not `getPoint()`)**  — it uses arc-length
parameterization, so the camera moves at constant speed regardless of
control point spacing.

### Object Transforms on Scroll

```javascript
gsap.to(mesh.rotation, {
  y: Math.PI * 2,
  scrollTrigger: { trigger: '#section', start: 'top center', end: 'bottom center', scrub: true }
});

gsap.fromTo(mesh.scale, { x: 0.5, y: 0.5, z: 0.5 }, {
  x: 1, y: 1, z: 1,
  scrollTrigger: { trigger: '#section', start: 'top 80%', end: 'top 20%', scrub: 0.8 }
});
```

### Shader Uniforms from Scroll

```javascript
gsap.to(material.uniforms.uProgress, {
  value: 1,
  scrollTrigger: { trigger: '.reveal', start: 'top bottom', end: 'top center', scrub: true }
});

// Distortion from velocity
ScrollTrigger.create({
  onUpdate: (self) => {
    const velocity = Math.abs(self.getVelocity()) / 1000;
    material.uniforms.uDistortion.value +=
      (Math.min(velocity, 1.0) - material.uniforms.uDistortion.value) * 0.1;
  }
});
```

### Master Timeline Approach

```javascript
const master = gsap.timeline({ paused: true });
master
  .add(cameraIntro, 0)
  .add(titleReveal, 0.1)
  .add(particleExplosion, 0.3)
  .add(productShowcase, 0.5)
  .add(outro, 0.8);

ScrollTrigger.create({
  trigger: '#experience',
  start: 'top top',
  end: 'bottom bottom',
  scrub: 1,
  onUpdate: (self) => master.progress(self.progress),
});
```

---

## 5. Smooth Scroll + Render Loop Sync

### Why They Desync

Browser scroll and `requestAnimationFrame` run on different threads/timing.
When you scroll, the compositor moves the page immediately (sometimes 120Hz),
but rAF fires at 60Hz. This creates 1-2 frame lag where DOM has scrolled
but WebGL has not updated — visible tearing.

### The Solution: Lenis + GSAP Ticker

```javascript
const lenis = new Lenis({ duration: 1.2, smoothWheel: true });
lenis.on('scroll', ScrollTrigger.update);

gsap.ticker.add((time) => {
  lenis.raf(time * 1000);
  renderer.render(scene, camera);
});
gsap.ticker.lagSmoothing(0);
```

### The Flow

```
User scrolls → Lenis intercepts → Smooth value → ScrollTrigger.update
     → gsap.ticker fires → lenis.raf() + ScrollTrigger + renderer.render()
     → All on the same frame, zero desync
```

---

## 6. Page Transitions (Barba.js)

### HTML: Canvas Outside Barba Wrapper

```html
<body>
  <canvas id="webgl"></canvas>  <!-- Persists across pages -->
  <nav>...</nav>                 <!-- Persists -->

  <div data-barba="wrapper">
    <main data-barba="container" data-barba-namespace="home">
      <!-- This gets swapped -->
    </main>
  </div>
</body>
```

### Barba Configuration

```javascript
barba.init({
  transitions: [{
    async leave({ current }) {
      ScrollTrigger.getAll().forEach(t => t.kill());
      canvas3D.disposePageMeshes();
      await gsap.to(current.container, { opacity: 0, duration: 0.5 });
      current.container.remove();
    },
    async enter({ next }) {
      lenis.scrollTo(0, { immediate: true });
      canvas3D.createPageMeshes(next.container);
      gsap.set(next.container, { opacity: 0 });
      await gsap.to(next.container, { opacity: 1, duration: 0.5 });
      ScrollTrigger.refresh();
      lenis.resize();
    }
  }]
});
```

### Memory Management During Transitions

```javascript
disposePageMeshes() {
  this.medias.forEach(media => {
    this.scene.remove(media.mesh);
    media.geometry.dispose();
    if (media.material.uniforms.uTexture?.value) {
      media.material.uniforms.uTexture.value.dispose();
    }
    media.material.dispose();
  });
  this.medias = [];
  this.renderer.renderLists.dispose();
}
```

---

## 7. Responsive WebGL

```javascript
class ResponsiveCanvas {
  constructor({ renderer, camera }) {
    this.renderer = renderer;
    this.camera = camera;
    this.onResize();
    window.addEventListener('resize', () => this.onResize());
  }

  onResize() {
    const w = window.innerWidth;
    const h = window.innerHeight;

    this.renderer.setSize(w, h);
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));

    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();

    const fovRad = (this.camera.fov * Math.PI) / 180;
    const distance = this.camera.position.z;
    this.viewport = {
      height: 2 * Math.tan(fovRad / 2) * distance,
      width: 2 * Math.tan(fovRad / 2) * distance * this.camera.aspect,
    };

    ScrollTrigger.refresh();
  }
}
```

### Adaptive Quality (drop DPR during scroll)

```javascript
lenis.on('scroll', () => {
  renderer.setPixelRatio(Math.min(devicePixelRatio, 1.5));
  clearTimeout(restoreTimer);
  restoreTimer = setTimeout(() => {
    renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
    renderer.render(scene, camera);
  }, 200);
});
```

### Mobile Config

```javascript
function getSceneConfig() {
  const w = window.innerWidth;
  if (w < 768) return { particles: 5000, shadows: false, postFx: false, maxDPR: 1.5 };
  if (w < 1200) return { particles: 15000, shadows: false, postFx: true, maxDPR: 2 };
  return { particles: 50000, shadows: true, postFx: true, maxDPR: 2 };
}
```

---

## 8. Performance Budgets

### Frame Budget

At 60fps: **16.67ms** per frame. Minus ~4ms browser overhead = **~12ms** for
your JS + GPU work. At 120fps (modern displays): **~4ms** JS budget.

### Monitoring

```javascript
const info = renderer.info;
setInterval(() => {
  console.log({
    fps: actualFPS,
    drawCalls: info.render.calls,
    triangles: info.render.triangles,
    textures: info.memory.textures,
    geometries: info.memory.geometries,
  });
  info.reset();
}, 5000);
```

### Budgets

| Metric | Mobile | Desktop |
|--------|--------|---------|
| Draw calls | < 50 | < 100 |
| Triangles/frame | < 300K | < 1M |
| Texture memory | < 50MB | < 100MB |
| Texture max size | 1024 | 2048 |
| Total page weight | < 5MB initial | < 8MB |
| LCP | < 2.5s | < 2.5s |
| Post-processing passes | 2-3 | 4-6 |

### Reducing Draw Calls

```javascript
// InstancedMesh: same geometry, different transforms, 1 draw call
const mesh = new THREE.InstancedMesh(geometry, material, 10000);
const dummy = new THREE.Object3D();
for (let i = 0; i < 10000; i++) {
  dummy.position.set(/*...*/);
  dummy.updateMatrix();
  mesh.setMatrixAt(i, dummy.matrix);
}

// Merge static geometry
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
const merged = mergeGeometries(geometries);
```

---

## 9. Complete Application Skeleton

```
src/
  index.html
  styles/main.css
  js/
    App.js              — Entry point, orchestrates everything
    Preloader.js         — Loading UI and gating
    AssetLoader.js       — THREE.LoadingManager wrapper
    Canvas.js            — Three.js scene, camera, renderer
    WebGLMedia.js        — DOM-to-WebGL sync per element
    SmoothScroll.js      — Lenis initialization
    shaders/
      reveal.vert
      reveal.frag
```

```javascript
// App.js — the orchestrator
class App {
  constructor() {
    this.lenis = new Lenis({ duration: 1.2, smoothWheel: true });
    this.lenis.on('scroll', ScrollTrigger.update);
    gsap.ticker.add((time) => this.lenis.raf(time * 1000));
    gsap.ticker.lagSmoothing(0);

    this.canvas = new Canvas({ canvas: document.getElementById('webgl'), lenis: this.lenis });
    this.preloader = new Preloader();
    this.preloader.start();
    this.queueAssets();

    window.addEventListener('preloader:complete', () => {
      this.createPageContent();
      this.setupScrollAnimations();
      this.canvas.startRenderLoop();
    });
  }
}
```
