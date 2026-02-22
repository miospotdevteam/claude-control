# Frontend Design Checklist

## Before

- [ ] Determine operating mode: greenfield (full creative freedom) or integration (existing design system)
- [ ] **Greenfield**: Score the 6 aesthetic axes (Audience, Formality, Energy, Density, Era, Temperature)
- [ ] **Greenfield**: Choose a creative seed — ONE unexpected element to anchor the design
- [ ] **Integration**: Read the existing design tokens, components, and 2-3 representative pages
- [ ] Select typography pairing (display + body) — check against anti-slop list
- [ ] Define color system with specific values (primary, secondary, accent, neutrals)
- [ ] Plan animation approach (which moments matter, what framework to use)

## During

### Accessibility

- [ ] Color contrast passes WCAG AA (4.5:1 for body text, 3:1 for large text/UI elements)
- [ ] Semantic HTML: headings in order, landmarks (`<nav>`, `<main>`, `<footer>`), buttons not divs
- [ ] Keyboard navigable: all interactive elements reachable via Tab, visible focus styles
- [ ] `prefers-reduced-motion` media query respected — animations disabled or simplified
- [ ] Images have meaningful `alt` text (or `alt=""` for decorative images)
- [ ] Form inputs have associated `<label>` elements

### Responsive

- [ ] Works at mobile (375px), tablet (768px), desktop (1280px) — no horizontal scroll
- [ ] Touch targets at least 44x44px on mobile
- [ ] Typography scales with viewport (use `clamp()` or responsive utilities, not just smaller sizes)
- [ ] Layout adapts meaningfully — not just stacking columns
- [ ] Images and media scale without overflow or distortion

### Performance

- [ ] Fonts loaded with `font-display: swap` or `optional` — no invisible text flash
- [ ] System font fallback metrics approximate the web font (minimize layout shift)
- [ ] Animations use `transform` and `opacity` only (GPU-composited, no layout triggers)
- [ ] No excessive DOM depth from decorative wrapper elements
- [ ] Large images use responsive sizing (`srcset`, `sizes`, or framework image components)

### Coherence

- [ ] All colors come from defined tokens/variables — no raw hex values in components
- [ ] Spacing follows a consistent scale (4px, 8px, 16px, etc. or Tailwind utilities)
- [ ] Typography uses defined type scale — no arbitrary font sizes
- [ ] Animation timing and easing consistent across similar interactions
- [ ] **Integration mode**: new work matches existing patterns for loading/error/empty states

## After

- [ ] Visual review: does the result match the intended aesthetic direction?
- [ ] Compare against the creative seed — is it present and effective?
- [ ] Test all breakpoints (mobile, tablet, desktop)
- [ ] Test with keyboard-only navigation
- [ ] **Integration mode**: compare side-by-side with existing pages for consistency
- [ ] Check that no anti-slop patterns crept in (generic gradients, overused fonts, template layouts)

## Red Flags

| Pattern | Problem |
|---|---|
| Inter/Roboto/Arial as display font | Generic AI aesthetic — choose a distinctive font |
| Purple-to-blue gradient on white | Most common AI color cliche |
| Every element fades in on scroll | Motion fatigue — be selective with animation |
| Raw hex colors instead of tokens | Will drift from the design system |
| Card grid with identical shadows | Template look — vary composition |
| No `prefers-reduced-motion` handling | Accessibility violation for motion-sensitive users |
| Arbitrary pixel values instead of scale | Spacing inconsistency over time |
| Display font from the anti-slop list | Check `frontend-design-guide.md` for alternatives |

## Deep Guidance

For the full aesthetic axis system, font sourcing protocol, animation patterns,
color systems, and anti-slop blacklist, read `frontend-design-guide.md`.

For design token discipline, component consistency, and drift detection, read
`ui-consistency-guide.md`.
