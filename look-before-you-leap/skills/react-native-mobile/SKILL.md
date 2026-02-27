---
name: react-native-mobile
description: "Build premium, native-feeling React Native mobile apps with spring animations, gesture-driven UI, haptic feedback, and platform-specific conventions. Use this skill whenever the user asks for: React Native app, mobile app, Expo app, native feel, gesture animations, haptic feedback, mobile UI, iOS/Android app, cross-platform mobile, Reanimated animations, bottom sheet, swipe gestures, pull-to-refresh, mobile navigation, tab bar, mobile onboarding, mobile performance, FlashList, MMKV storage, offline-first mobile, React Native new architecture, mobile dark mode, Dynamic Type, VoiceOver/TalkBack accessibility, or any request for building mobile applications that should feel indistinguishable from native apps. Also use when the user references apps like Things 3, Apollo, Spotify, or Apple's HIG / Material Design 3. Do NOT use for: React web apps (use frontend-design), React Native Web without mobile focus, backend APIs, or admin dashboards — this skill is exclusively for native mobile experiences."
---

# React Native Mobile

Build mobile apps that feel indistinguishable from native. Spring-driven
animations, gesture-first interactions, haptic feedback on every state
change, and platform conventions that make iOS users feel at home on iOS
and Android users feel at home on Android.

**Announce at start:** "I'm using the react-native-mobile skill to build
this mobile experience."

---

## Prerequisites

This skill operates within the conductor's Step 1-3:

- **Phase 1** (Assessment) runs during Step 1 (Explore).
- **Phase 2** (Architecture) feeds into the masterPlan via `writing-plans`.
- **Phase 3** (Implementation) runs during Step 3 (Execute).
- **Phase 4** (Verification) runs after implementation.

If `brainstorming` ran first and produced design direction: use those
decisions and skip to Phase 2.

---

## Phase 1: Assessment — What Are We Building?

### Decision Tree

Answer these questions to determine scope and which references to read:

```
Does it need gesture-driven interactions?
├── YES → Read: references/gesture-cookbook.md
│   ├── Complex animations (shared elements, layout)? → Also read: references/animation-patterns.md
│   ├── Lists with swipe actions or drag-to-reorder? → Also read: references/performance-patterns.md
│   └── Platform-specific gesture conventions? → Also read: references/platform-patterns.md
│
└── NO (standard screens, forms, navigation)
    └── Read: references/component-recipes.md + references/platform-patterns.md
```

**Always read:** `references/architecture.md` for app structure, navigation,
state management, and storage — these apply to every React Native app.

### Complexity Tiers

| Tier | Description | Stack | Reference Files |
|------|-------------|-------|-----------------|
| **Polished Standard** | Clean screens, smooth navigation, proper platform conventions. No custom gestures. | Expo + Expo Router + Zustand + MMKV | architecture, platform-patterns, component-recipes |
| **Motion-Rich** | Spring animations, shared element transitions, animated lists, haptic feedback on interactions. | + Reanimated + Moti + expo-haptics | + animation-patterns, gesture-cookbook |
| **Full Premium** | Custom gesture-driven UI, drag-to-reorder, swipe choreography, physics-based interactions, offline-first. | + Gesture Handler + FlashList + TanStack Query + WatermelonDB | All reference files |

---

## Phase 2: Architecture

### Quick-Start Structure (Every React Native App)

```
┌─────────────────────────────────────────┐
│  APP SHELL (Expo Router)                │  ← File-based routing, layouts
│  - _layout.tsx at each level            │
│  - Auth guard in root layout            │
│  - Tab navigator with platform styling  │
├─────────────────────────────────────────┤
│  SCREEN LAYER                           │  ← Feature-organized screens
│  - Each feature owns its screens        │
│  - Shared UI components in /components  │
│  - Platform-specific files: .ios / .android │
├─────────────────────────────────────────┤
│  DATA LAYER                             │  ← State + persistence
│  - Zustand for client state             │
│  - TanStack Query for server state      │
│  - MMKV for fast key-value storage      │
│  - Optimistic updates for offline       │
├─────────────────────────────────────────┤
│  NATIVE BRIDGE                          │  ← Platform APIs
│  - expo-haptics for tactile feedback    │
│  - Reanimated worklets on UI thread     │
│  - Gesture Handler for native gestures  │
│  - expo-* modules for device APIs       │
└─────────────────────────────────────────┘
```

### Technology Selection Guide

| Need | Use | Why |
|------|-----|-----|
| App framework | **Expo SDK 52+** | Managed workflow, EAS Build, OTA updates |
| Navigation | **Expo Router v4** | File-based routing, deep linking, type-safe |
| Animations | **Reanimated 4** | Worklets run on UI thread, 60fps guaranteed |
| Declarative animations | **Moti** | Reanimated wrapper, simpler API for common cases |
| Gestures | **Gesture Handler v2** | Native gesture recognition, composable |
| Lists | **FlashList** | Recycling, 5x faster than FlatList |
| Client state | **Zustand** | Minimal, no providers, works outside React |
| Server state | **TanStack Query v5** | Cache, background refresh, optimistic updates |
| Fast storage | **MMKV** | 30x faster than AsyncStorage, synchronous |
| Structured storage | **expo-sqlite** | SQL queries, migrations, larger datasets |
| Haptics | **expo-haptics** | Cross-platform haptic feedback |
| Icons | **expo-symbols** (iOS) + **Material Icons** | Platform-native icon sets |
| Forms | **React Hook Form + Zod** | Performant, type-safe validation |

---

## Phase 3: Implementation Rules

### 12 Critical Rules

1. **Springs over easing.** Use `withSpring()` for interactive animations,
   never `withTiming()` with easing curves for things the user touches.
   Springs have natural deceleration; easing curves feel artificial.

2. **FlashList always.** Never use `FlatList` or `ScrollView` for lists
   with more than ~20 items. FlashList recycles views, uses fraction of
   the memory, and maintains 60fps.

3. **MMKV always.** Never use `AsyncStorage` — it's async, slow, and
   JSON-serializes everything. MMKV is synchronous and 30x faster.

4. **Transform-only animations.** Animate `transform` (translateX/Y,
   scale, rotate) and `opacity` only. Never animate `width`, `height`,
   `top`, `left`, `margin`, `padding` — these trigger layout recalculation.

5. **Haptics on state changes.** Every meaningful state transition gets
   haptic feedback: toggle switches (`impactLight`), destructive actions
   (`notificationWarning`), success (`notificationSuccess`), button press
   (`impactMedium`), selection change (`selectionChanged`).

6. **Platform-specific conventions.** iOS gets SF Symbols, large titles,
   swipe-back navigation, sheets. Android gets Material Icons, top app bar,
   predictive back gesture, bottom sheets. Use `.ios.tsx` / `.android.tsx`
   when conventions diverge significantly.

7. **Safe areas everywhere.** Use `useSafeAreaInsets()` from
   `react-native-safe-area-context`. Never hardcode status bar heights.
   Account for Dynamic Island, home indicator, and navigation bar.

8. **Dark mode from day one.** Use semantic color tokens that respond to
   `useColorScheme()`. Never hardcode colors. Define a theme object with
   `light` and `dark` variants.

9. **Keyboard-aware forms.** Use `KeyboardAvoidingView` (with
   `behavior="padding"` on iOS, `behavior="height"` on Android) or
   `react-native-keyboard-aware-scroll-view`. Never let the keyboard
   obscure input fields.

10. **Accessible by default.** Every touchable has `accessibilityRole` and
    `accessibilityLabel`. Test with VoiceOver (iOS) and TalkBack (Android).
    Support Dynamic Type — never use fixed font sizes without scaling.

11. **Optimistic updates.** For any user-initiated mutation, update the UI
    immediately and sync in the background. Revert on failure with a toast.
    Users should never wait for a network round-trip to see their action.

12. **Preload before render.** Use `expo-splash-screen` to hold the splash
    until fonts, initial data, and auth state are loaded. No layout flash,
    no loading spinners on app open.

### Anti-Patterns — What NOT to Do

| Anti-Pattern | Why It Fails | Do This Instead |
|---|---|---|
| `withTiming` for interactive elements | Feels robotic, no natural deceleration | `withSpring({ damping: 15, stiffness: 150 })` |
| FlatList for long lists | No view recycling, memory grows linearly | FlashList with `estimatedItemSize` |
| AsyncStorage | Async, slow, JSON serialization overhead | MMKV for key-value, expo-sqlite for structured |
| Animating `width`/`height` | Triggers layout on every frame, drops to 30fps | Transform: `scale`, `translateX/Y` |
| Hardcoded status bar height | Breaks on notch, Dynamic Island, Android nav bar | `useSafeAreaInsets()` |
| `any` / `as any` in TypeScript | Hides bugs, no autocomplete, runtime crashes | Proper types, let inference work |
| `setTimeout` for animation sequencing | Unreliable timing, missed frames, no cancellation | `withSequence()`, `withDelay()`, or Moti transitions |
| Inline styles in animated components | Creates new style objects every render | `useAnimatedStyle()` with Reanimated |
| No haptic feedback | App feels lifeless, like a web wrapper | expo-haptics on every meaningful interaction |
| Fixed font sizes | Breaks for users with accessibility scaling | Use relative sizes, respect Dynamic Type |
| Synchronous heavy computation | Blocks JS thread, gestures freeze | Move to worklet or background thread |
| `useEffect` for data fetching | No cache, no background refresh, waterfall loads | TanStack Query with `useQuery` |

---

## Phase 4: Verification

### Mobile-Specific Checklist

- [ ] **60fps**: No frame drops during scrolling and animations (check Perf Monitor)
- [ ] **VoiceOver / TalkBack**: Full screen reader navigation works, all elements labeled
- [ ] **Dark mode**: All screens render correctly in both light and dark
- [ ] **Dynamic Type**: Text scales with system font size settings
- [ ] **Platform gestures**: Swipe-back (iOS), predictive back (Android) work correctly
- [ ] **Haptics**: Meaningful haptic feedback on state changes and interactions
- [ ] **Offline**: App handles no-network gracefully (cached data, error states)
- [ ] **Safe areas**: Content respects notch, Dynamic Island, home indicator
- [ ] **Keyboard**: Forms remain visible and usable with keyboard open
- [ ] **Splash screen**: No layout flash or loading spinner on app launch

### Standard Checks (from engineering-discipline)

- [ ] Type checker passes (`tsc --noEmit` or `npx expo-doctor`)
- [ ] Linter passes
- [ ] No `any` / `as any` in TypeScript
- [ ] Tests pass (if test infrastructure exists)

---

## Reference Files

| File | Contents | When to Read |
|------|----------|--------------|
| `references/architecture.md` | App structure, Expo Router, state management, storage tiers, offline patterns | Every React Native project |
| `references/animation-patterns.md` | Reanimated 4, springs, shared elements, Moti, entering/exiting, layout animations | Any animation work |
| `references/gesture-cookbook.md` | 8 complete gesture implementations (pull-to-refresh, swipe, bottom sheet, etc.) | Building gesture-driven UI |
| `references/platform-patterns.md` | iOS vs Android conventions, safe areas, haptics, dark mode, typography | Platform-specific decisions |
| `references/performance-patterns.md` | FlashList, startup optimization, bundle analysis, images, MMKV, New Architecture | Performance optimization |
| `references/component-recipes.md` | 8 complete component implementations (skeleton, error boundary, toast, etc.) | Building common UI patterns |

### Routing to Other Skills

| Need | Skill |
|------|-------|
| Creative direction brainstorming | `brainstorming` |
| Implementation planning | `writing-plans` |
| Testing strategy | `test-driven-development` |
| Debugging issues | `systematic-debugging` |

---

## Output Contract

This skill produces:

1. **Architecture decisions** in `discovery.md` — tier selection, tech stack,
   platform strategy, performance budget
2. **Working code** — TypeScript React Native components with Expo, Reanimated,
   Gesture Handler, proper platform conventions
3. **Verification results** in masterPlan step Results — fps confirmed,
   accessibility tested, dark mode verified, haptics working
