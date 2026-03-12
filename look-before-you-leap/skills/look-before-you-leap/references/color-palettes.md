# Curated Color Palettes

Ready-to-use CSS custom property sets for standalone HTML files. Each
palette includes light and dark mode tokens, semantic naming, and
accessibility-tested contrast ratios.

Pick the palette that matches the Temperature + Energy axes from the
design direction, then customize the primary/accent hues to fit the brand.

---

## How to use

1. Copy the `:root` and `.dark` blocks into your `<style>`
2. Swap the primary/accent hue values to match your creative seed
3. Keep the lightness/saturation relationships — they're tuned for contrast
4. Reference tokens by name in your CSS: `color: var(--text-primary)`

---

## Warm Cream (Temperature 1-3, casual/creative brands)

Best for: creative agencies, portfolios, lifestyle, food, education,
personal brands. Light cream background with warm neutrals.

```css
:root {
  /* Surfaces */
  --surface-0: #faf6f1;
  --surface-1: #f3ede5;
  --surface-2: #ebe3d8;
  --surface-raised: #ffffff;

  /* Text */
  --text-primary: #1a1714;
  --text-secondary: #5c554b;
  --text-muted: #8a8279;

  /* Primary — terracotta (swap hue to match brand) */
  --primary: #c4623a;
  --primary-hover: #b5542d;
  --primary-light: #fdf0eb;
  --primary-on: #ffffff;

  /* Accent — teal (complementary warmth balance) */
  --accent: #2b6b5e;
  --accent-hover: #235a4f;
  --accent-light: #e8f5f1;
  --accent-on: #ffffff;

  /* Borders & UI */
  --border: #e0d8cd;
  --border-hover: #ccc2b4;
  --ring: rgba(196, 98, 58, 0.4);

  /* Shadows */
  --shadow-sm: 0 1px 2px rgba(26, 23, 20, 0.06);
  --shadow-md: 0 4px 12px rgba(26, 23, 20, 0.08);
  --shadow-lg: 0 12px 32px rgba(26, 23, 20, 0.12);
}

.dark, [data-theme="dark"] {
  --surface-0: #14120f;
  --surface-1: #1e1b17;
  --surface-2: #282420;
  --surface-raised: #302c27;

  --text-primary: #ede8e1;
  --text-secondary: #a89f94;
  --text-muted: #6e665c;

  --primary: #e07a52;
  --primary-hover: #d4673f;
  --primary-light: rgba(224, 122, 82, 0.12);
  --primary-on: #14120f;

  --accent: #4fd1b5;
  --accent-hover: #3bbfa3;
  --accent-light: rgba(79, 209, 181, 0.1);
  --accent-on: #14120f;

  --border: #352f29;
  --border-hover: #443d35;
  --ring: rgba(224, 122, 82, 0.4);

  --shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.3);
  --shadow-md: 0 4px 12px rgba(0, 0, 0, 0.4);
  --shadow-lg: 0 12px 32px rgba(0, 0, 0, 0.5);
}
```

### Warm hue variants

Swap `--primary` values for different warm brands:

| Brand feel | Primary hue | Hex base |
|---|---|---|
| Terracotta / earthy | `#c4623a` | (default above) |
| Coral / energetic | `#e06456` | warm red-orange |
| Golden amber / premium | `#c98a2e` | warm gold |
| Sage / natural | `#6b8f71` | muted green |
| Dusty rose / soft | `#c27082` | muted pink |

---

## Cool Slate (Temperature 4-5, technical/analytical brands)

Best for: developer tools, analytics platforms, SaaS dashboards,
documentation sites, fintech. Cool blue-gray base with sharp accents.

```css
:root {
  /* Surfaces */
  --surface-0: #f8fafb;
  --surface-1: #f0f3f5;
  --surface-2: #e6eaed;
  --surface-raised: #ffffff;

  /* Text */
  --text-primary: #0f1419;
  --text-secondary: #4a5568;
  --text-muted: #7b8794;

  /* Primary — teal (swap hue to match brand) */
  --primary: #0d9488;
  --primary-hover: #0b7c72;
  --primary-light: #e6faf8;
  --primary-on: #ffffff;

  /* Accent — amber (warm contrast on cool base) */
  --accent: #d97706;
  --accent-hover: #b45309;
  --accent-light: #fef3e2;
  --accent-on: #ffffff;

  /* Borders & UI */
  --border: #dce1e6;
  --border-hover: #c4ccd4;
  --ring: rgba(13, 148, 136, 0.4);

  /* Shadows */
  --shadow-sm: 0 1px 2px rgba(15, 20, 25, 0.05);
  --shadow-md: 0 4px 12px rgba(15, 20, 25, 0.07);
  --shadow-lg: 0 12px 32px rgba(15, 20, 25, 0.1);
}

.dark, [data-theme="dark"] {
  --surface-0: #0b0f12;
  --surface-1: #131a20;
  --surface-2: #1a2330;
  --surface-raised: #1e2a38;

  --text-primary: #e2e8f0;
  --text-secondary: #94a3b8;
  --text-muted: #5a6a7e;

  --primary: #2dd4bf;
  --primary-hover: #14b8a6;
  --primary-light: rgba(45, 212, 191, 0.1);
  --primary-on: #0b0f12;

  --accent: #fbbf24;
  --accent-hover: #f59e0b;
  --accent-light: rgba(251, 191, 36, 0.1);
  --accent-on: #0b0f12;

  --border: #1e2d3d;
  --border-hover: #2a3f52;
  --ring: rgba(45, 212, 191, 0.4);

  --shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.3);
  --shadow-md: 0 4px 12px rgba(0, 0, 0, 0.4);
  --shadow-lg: 0 12px 32px rgba(0, 0, 0, 0.5);
}
```

### Cool hue variants

| Brand feel | Primary hue | Hex base |
|---|---|---|
| Teal / science | `#0d9488` | (default above) |
| Electric blue / tech | `#3b82f6` | bright blue |
| Indigo / enterprise | `#6366f1` | blue-purple |
| Emerald / growth | `#059669` | green |
| Cyan / data | `#06b6d4` | light blue |

---

## Dark Gallery (Temperature 3-5, editorial/gallery/photography)

Best for: photography portfolios, art galleries, luxury brands, editorial
sites. Dark backgrounds that make visual content pop.

```css
:root {
  /* Surfaces — warm-tinted near-blacks */
  --surface-0: #0a0a09;
  --surface-1: #141312;
  --surface-2: #1e1d1b;
  --surface-raised: #282624;

  /* Text — warm ivory, not pure white */
  --text-primary: #f0ece4;
  --text-secondary: #a8a29e;
  --text-muted: #6b6560;

  /* Primary — stone/taupe (understated, lets content shine) */
  --primary: #a89080;
  --primary-hover: #bda494;
  --primary-light: rgba(168, 144, 128, 0.12);
  --primary-on: #0a0a09;

  /* Accent — warm gold (for CTAs and highlights) */
  --accent: #c9a84c;
  --accent-hover: #d4b65e;
  --accent-light: rgba(201, 168, 76, 0.1);
  --accent-on: #0a0a09;

  /* Borders & UI */
  --border: #2a2826;
  --border-hover: #3a3734;
  --ring: rgba(168, 144, 128, 0.4);

  /* Shadows — subtle on dark */
  --shadow-sm: 0 1px 3px rgba(0, 0, 0, 0.4);
  --shadow-md: 0 4px 12px rgba(0, 0, 0, 0.5);
  --shadow-lg: 0 12px 32px rgba(0, 0, 0, 0.6);
}
```

---

## Neutral Minimal (Temperature 3, balanced/modern brands)

Best for: documentation, blogs, corporate sites, anything where content
is king and design should stay out of the way.

```css
:root {
  --surface-0: #fafafa;
  --surface-1: #f4f4f5;
  --surface-2: #e4e4e7;
  --surface-raised: #ffffff;

  --text-primary: #18181b;
  --text-secondary: #52525b;
  --text-muted: #a1a1aa;

  --primary: #18181b;
  --primary-hover: #27272a;
  --primary-light: #f4f4f5;
  --primary-on: #ffffff;

  --accent: #dc2626;
  --accent-hover: #b91c1c;
  --accent-light: #fef2f2;
  --accent-on: #ffffff;

  --border: #e4e4e7;
  --border-hover: #d4d4d8;
  --ring: rgba(24, 24, 27, 0.3);

  --shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.04);
  --shadow-md: 0 4px 8px rgba(0, 0, 0, 0.06);
  --shadow-lg: 0 12px 24px rgba(0, 0, 0, 0.08);
}

.dark, [data-theme="dark"] {
  --surface-0: #09090b;
  --surface-1: #18181b;
  --surface-2: #27272a;
  --surface-raised: #2d2d30;

  --text-primary: #fafafa;
  --text-secondary: #a1a1aa;
  --text-muted: #52525b;

  --primary: #fafafa;
  --primary-hover: #e4e4e7;
  --primary-light: rgba(250, 250, 250, 0.08);
  --primary-on: #09090b;

  --accent: #ef4444;
  --accent-hover: #dc2626;
  --accent-light: rgba(239, 68, 68, 0.1);
  --accent-on: #ffffff;

  --border: #27272a;
  --border-hover: #3f3f46;
  --ring: rgba(250, 250, 250, 0.3);

  --shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.4);
  --shadow-md: 0 4px 8px rgba(0, 0, 0, 0.5);
  --shadow-lg: 0 12px 24px rgba(0, 0, 0, 0.6);
}
```

---

## Usage rules

1. **Always start from a palette** — never generate colors ad hoc. Pick
   the closest palette, then adjust the primary/accent hue
2. **Keep the lightness relationships** — the light/dark ratios in each
   palette are tuned for WCAG AA contrast. Changing the hue is safe;
   changing the lightness can break contrast
3. **Test primary-on-surface** — `--primary` text on `--surface-0` must
   pass 4.5:1 contrast. `--primary-on` text on `--primary` must also pass
4. **Use semantic names** — never use raw hex values in components. Always
   reference `var(--text-primary)`, `var(--surface-1)`, etc.
5. **Dark mode is not inverted** — each palette has carefully adapted dark
   variants. Don't just swap light/dark values mechanically
