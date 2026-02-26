# Three.js Patterns

Complete patterns for Three.js scene setup, React Three Fiber, particles,
post-processing, and memory management.

---

## 1. Vanilla Three.js Scene Setup

```javascript
import * as THREE from 'three';

// --- Scene ---
const scene = new THREE.Scene();
scene.background = new THREE.Color(0x0a0a0a);
scene.fog = new THREE.Fog(0x0a0a0a, 10, 50);

// --- Camera ---
const camera = new THREE.PerspectiveCamera(
  50,                                     // fov
  window.innerWidth / window.innerHeight, // aspect
  0.1,                                    // near
  100                                     // far
);
camera.position.set(0, 1.5, 5);

// --- Renderer ---
const renderer = new THREE.WebGLRenderer({
  canvas: document.getElementById('webgl'),
  antialias: true,
  alpha: true, // transparent background for DOM layering
});
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.0;

// --- Lighting ---
const ambientLight = new THREE.AmbientLight(0xffffff, 0.4);
scene.add(ambientLight);

const directionalLight = new THREE.DirectionalLight(0xffffff, 1.0);
directionalLight.position.set(5, 10, 5);
directionalLight.castShadow = true;
directionalLight.shadow.mapSize.set(2048, 2048);
scene.add(directionalLight);

// --- Resize Handler ---
window.addEventListener('resize', () => {
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(window.innerWidth, window.innerHeight);
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
});
```

**Key rules:**
- Always call `camera.updateProjectionMatrix()` after changing camera properties
- Cap `devicePixelRatio` at 2 to avoid GPU overload on high-DPI screens
- Use `alpha: true` when layering canvas over DOM content

---

## 2. PBR Materials

```javascript
const textureLoader = new THREE.TextureLoader();

const material = new THREE.MeshStandardMaterial({
  map: textureLoader.load('/textures/albedo.jpg'),
  normalMap: textureLoader.load('/textures/normal.jpg'),
  roughnessMap: textureLoader.load('/textures/roughness.jpg'),
  metalnessMap: textureLoader.load('/textures/metalness.jpg'),
  roughness: 0.5,
  metalness: 0.5,
});

// Environment map (essential for metallic surfaces)
import { RGBELoader } from 'three/addons/loaders/RGBELoader.js';
const rgbeLoader = new RGBELoader();
rgbeLoader.load('/textures/env.hdr', (texture) => {
  texture.mapping = THREE.EquirectangularReflectionMapping;
  scene.environment = texture;
});
```

**Always provide an environment map** with MeshStandardMaterial. Without one,
metallic surfaces appear black — they rely on reflections.

---

## 3. Custom ShaderMaterial

```javascript
const material = new THREE.ShaderMaterial({
  uniforms: {
    uTime:       { value: 0 },
    uColor:      { value: new THREE.Color(0x00ffaa) },
    uResolution: { value: new THREE.Vector2(window.innerWidth, window.innerHeight) },
    uTexture:    { value: textureLoader.load('/textures/noise.png') },
  },
  vertexShader: /* glsl */ `
    uniform float uTime;
    varying vec2 vUv;
    varying float vElevation;

    void main() {
      vUv = uv;
      vec3 pos = position;
      float elevation = sin(pos.x * 4.0 + uTime) * 0.2;
      pos.z += elevation;
      vElevation = elevation;
      gl_Position = projectionMatrix * modelViewMatrix * vec4(pos, 1.0);
    }
  `,
  fragmentShader: /* glsl */ `
    uniform vec3 uColor;
    uniform sampler2D uTexture;
    varying vec2 vUv;
    varying float vElevation;

    void main() {
      vec4 texColor = texture2D(uTexture, vUv);
      float brightness = vElevation * 2.0 + 0.5;
      gl_FragColor = vec4(uColor * texColor.rgb * brightness, 1.0);
    }
  `,
  side: THREE.DoubleSide,
});
```

**Built-in uniforms** (auto-injected by ShaderMaterial):
- `projectionMatrix`, `modelViewMatrix`, `viewMatrix`, `modelMatrix`, `normalMatrix`

**Built-in attributes:**
- `position` (vec3), `normal` (vec3), `uv` (vec2)

Use `RawShaderMaterial` when you need zero injection (GLSL 300 es, full control).

---

## 4. GLTF Model Loading

```javascript
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { DRACOLoader } from 'three/addons/loaders/DRACOLoader.js';

const dracoLoader = new DRACOLoader();
dracoLoader.setDecoderPath('/draco/');

const gltfLoader = new GLTFLoader();
gltfLoader.setDRACOLoader(dracoLoader);

gltfLoader.load('/models/scene.glb', (gltf) => {
  const model = gltf.scene;
  model.traverse((child) => {
    if (child.isMesh) {
      child.castShadow = true;
      child.receiveShadow = true;
    }
  });
  scene.add(model);
});
```

---

## 5. Raycasting

```javascript
const raycaster = new THREE.Raycaster();
const pointer = new THREE.Vector2();

window.addEventListener('pointermove', (e) => {
  pointer.x = (e.clientX / window.innerWidth) * 2 - 1;
  pointer.y = -(e.clientY / window.innerHeight) * 2 + 1;
});

// In render loop or on click:
raycaster.setFromCamera(pointer, camera);
const intersects = raycaster.intersectObjects(scene.children, true);

if (intersects.length > 0) {
  const hit = intersects[0];
  // hit.object, hit.point, hit.face.normal, hit.uv, hit.distance
}
```

---

## 6. Particle Systems

### Basic PointsMaterial

```javascript
const count = 50000;
const geometry = new THREE.BufferGeometry();
const positions = new Float32Array(count * 3);

for (let i = 0; i < count * 3; i++) {
  positions[i] = (Math.random() - 0.5) * 50;
}
geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));

const material = new THREE.PointsMaterial({
  size: 3,
  sizeAttenuation: true,
  transparent: true,
  alphaTest: 0.01,
  blending: THREE.AdditiveBlending,
  depthWrite: false,
  map: textureLoader.load('/textures/particle.png'),
});

const particles = new THREE.Points(geometry, material);
scene.add(particles);
```

### Custom Shader Particles

```javascript
const particleGeometry = new THREE.BufferGeometry();
const count = 20000;
const positions = new Float32Array(count * 3);
const randoms = new Float32Array(count);
const scales = new Float32Array(count);

for (let i = 0; i < count; i++) {
  const radius = Math.random() * 20;
  const angle = Math.random() * Math.PI * 2;
  positions[i * 3]     = Math.cos(angle) * radius;
  positions[i * 3 + 1] = (Math.random() - 0.5) * 4;
  positions[i * 3 + 2] = Math.sin(angle) * radius;
  randoms[i] = Math.random();
  scales[i] = Math.random();
}

particleGeometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
particleGeometry.setAttribute('aRandom', new THREE.BufferAttribute(randoms, 1));
particleGeometry.setAttribute('aScale', new THREE.BufferAttribute(scales, 1));

const particleMaterial = new THREE.ShaderMaterial({
  uniforms: {
    uTime: { value: 0 },
    uPixelRatio: { value: renderer.getPixelRatio() },
    uSize: { value: 100.0 },
  },
  vertexShader: /* glsl */ `
    uniform float uTime;
    uniform float uPixelRatio;
    uniform float uSize;
    attribute float aRandom;
    attribute float aScale;
    varying float vRandom;

    void main() {
      vec3 pos = position;
      // Rotate around Y axis
      float angle = atan(pos.x, pos.z);
      float dist = length(pos.xz);
      angle += (1.0 / dist) * uTime * 0.2;
      pos.x = cos(angle) * dist;
      pos.z = sin(angle) * dist;
      pos.y += sin(uTime + aRandom * 6.28) * 0.3;

      vec4 mvPos = modelViewMatrix * vec4(pos, 1.0);
      gl_PointSize = uSize * aScale * uPixelRatio * (1.0 / -mvPos.z);
      gl_Position = projectionMatrix * mvPos;
      vRandom = aRandom;
    }
  `,
  fragmentShader: /* glsl */ `
    varying float vRandom;
    void main() {
      float dist = length(gl_PointCoord - vec2(0.5));
      if (dist > 0.5) discard;
      float alpha = 1.0 - smoothstep(0.3, 0.5, dist);
      vec3 color = mix(vec3(0.2, 0.5, 1.0), vec3(1.0, 0.3, 0.6), vRandom);
      gl_FragColor = vec4(color, alpha);
    }
  `,
  transparent: true,
  blending: THREE.AdditiveBlending,
  depthWrite: false,
});

const particles = new THREE.Points(particleGeometry, particleMaterial);
scene.add(particles);
```

**Key particle rules:**
- `gl_PointSize *= (1.0 / -mvPosition.z)` for proper size attenuation
- `gl_PointCoord` in fragment shader (vec2, 0-1) for per-particle shapes
- `depthWrite: false` + `AdditiveBlending` for glowing overlapping particles

---

## 7. Post-Processing (EffectComposer)

```javascript
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';

const composer = new EffectComposer(renderer);

// 1. Render scene to framebuffer (always first)
composer.addPass(new RenderPass(scene, camera));

// 2. Bloom
const bloomPass = new UnrealBloomPass(
  new THREE.Vector2(window.innerWidth, window.innerHeight),
  1.5,  // strength
  0.4,  // radius
  0.85  // threshold
);
composer.addPass(bloomPass);

// 3. Custom shader pass (example: vignette)
const vignettePass = new ShaderPass({
  uniforms: {
    tDiffuse: { value: null }, // Auto-filled by EffectComposer
    uIntensity: { value: 0.7 },
  },
  vertexShader: /* glsl */ `
    varying vec2 vUv;
    void main() { vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }
  `,
  fragmentShader: /* glsl */ `
    uniform sampler2D tDiffuse;
    uniform float uIntensity;
    varying vec2 vUv;
    void main() {
      vec4 color = texture2D(tDiffuse, vUv);
      float dist = length(vUv - 0.5);
      color.rgb *= smoothstep(0.5, 0.5 - uIntensity, dist);
      gl_FragColor = color;
    }
  `,
});
composer.addPass(vignettePass);

// 4. Output pass (color space correction — always last)
composer.addPass(new OutputPass());

// Use composer.render() instead of renderer.render()
// Handle resize: composer.setSize(w, h) alongside renderer.setSize()
```

**Post-processing rules:**
- `RenderPass` always first, `OutputPass` always last
- `tDiffuse` is the convention — EffectComposer auto-fills it
- Keep to 3-5 passes max for 60fps on mobile
- Combine small effects into one shader pass to reduce render target switches

---

## 8. React Three Fiber (R3F)

```jsx
import { Canvas, useFrame, useThree } from '@react-three/fiber';
import { Environment, Float, Text, Html, MeshDistortMaterial } from '@react-three/drei';
import { EffectComposer, Bloom, Vignette, ChromaticAberration } from '@react-three/postprocessing';

function AnimatedMesh() {
  const meshRef = useRef();
  const [hovered, setHovered] = useState(false);

  useFrame((state, delta) => {
    meshRef.current.rotation.y += delta * 0.3;
    // state.clock, state.pointer, state.camera, state.viewport
  });

  return (
    <mesh ref={meshRef}
      onPointerOver={() => setHovered(true)}
      onPointerOut={() => setHovered(false)}>
      <sphereGeometry args={[1, 64, 64]} />
      <MeshDistortMaterial color="#8b5cf6" distort={0.5} speed={2} />
    </mesh>
  );
}

function Effects() {
  return (
    <EffectComposer>
      <Bloom luminanceThreshold={0.6} intensity={1.5} mipmapBlur />
      <ChromaticAberration offset={[0.002, 0.002]} />
      <Vignette offset={0.3} darkness={0.9} />
    </EffectComposer>
  );
}

export default function App() {
  return (
    <Canvas dpr={[1, 2]} camera={{ fov: 50, position: [0, 2, 5] }} shadows>
      <ambientLight intensity={0.4} />
      <directionalLight position={[5, 10, 5]} intensity={1.2} castShadow />
      <Environment preset="sunset" />
      <Float speed={1.5} rotationIntensity={1} floatIntensity={2}>
        <AnimatedMesh />
      </Float>
      <Effects />
    </Canvas>
  );
}
```

**R3F rules:**
- Hooks (`useFrame`, `useThree`) only work inside `<Canvas>`
- Never call `setState` inside `useFrame` — mutate refs instead
- R3F auto-handles disposal on unmount
- Use `gsap.context()` for GSAP cleanup in React components

---

## 9. Performance Optimization

### InstancedMesh (reduce draw calls 90%+)

```javascript
const count = 10000;
const mesh = new THREE.InstancedMesh(geometry, material, count);
const dummy = new THREE.Object3D();

for (let i = 0; i < count; i++) {
  dummy.position.set(Math.random() * 50, Math.random() * 50, Math.random() * 50);
  dummy.rotation.set(Math.random() * Math.PI, Math.random() * Math.PI, 0);
  dummy.updateMatrix();
  mesh.setMatrixAt(i, dummy.matrix);
}
mesh.instanceMatrix.needsUpdate = true;
scene.add(mesh); // 1 draw call for 10,000 objects
```

### Performance Monitoring

```javascript
// Check every few seconds
setInterval(() => {
  console.log({
    drawCalls: renderer.info.render.calls,
    triangles: renderer.info.render.triangles,
    textures: renderer.info.memory.textures,
    geometries: renderer.info.memory.geometries,
  });
  renderer.info.reset();
}, 5000);
```

### Budget

| Metric | Mobile | Desktop |
|--------|--------|---------|
| Draw calls | < 50 | < 100 |
| Triangles/frame | < 300K | < 1M |
| Texture memory | < 50MB | < 100MB |
| JS frame time | < 12ms | < 12ms |

---

## 10. Memory Disposal

```javascript
function disposeObject(object) {
  if (object.geometry) object.geometry.dispose();
  if (object.material) {
    const materials = Array.isArray(object.material) ? object.material : [object.material];
    materials.forEach(mat => {
      ['map','normalMap','roughnessMap','metalnessMap','aoMap',
       'emissiveMap','displacementMap','alphaMap','envMap'].forEach(key => {
        if (mat[key]) mat[key].dispose();
      });
      mat.dispose();
    });
  }
}

// Dispose entire scene
function disposeScene(scene) {
  scene.traverse(disposeObject);
  scene.clear();
}

// Full cleanup
function cleanup() {
  renderer.setAnimationLoop(null);
  disposeScene(scene);
  if (composer) {
    composer.renderTarget1.dispose();
    composer.renderTarget2.dispose();
  }
  renderer.dispose();
  renderer.domElement.remove();
}
```

**Disposal rules:**
- GPU resources are NOT garbage collected — always call `.dispose()`
- Shared textures: don't dispose if still used elsewhere
- Monitor `renderer.info.memory` to verify resources are freed
- In SPAs/page transitions, dispose everything from the old page
