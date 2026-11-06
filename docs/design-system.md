# Yisi Design System

## Direction: Precision & Restraint
Swiss minimalism with serif elegance. Subtle borders define structure, shadows reinforce interaction. Every element earns its place.

## Surfaces

Two UI surfaces share a unified identity with platform-appropriate expression:

| Property | App (SwiftUI) | Web (React + CSS) |
|----------|---------------|-------------------|
| Framework | SwiftUI | React + vanilla CSS |
| Typography | System serif (.design(.serif)) | Instrument Serif / Noto Serif SC / Inter / IBM Plex Mono |
| Depth | Glass morphism (.hudWindow) | Glass backdrop-filter + border |
| Layout | Native panels/windows | 1080px max, 3-col grid |

---

## Spacing

### Unified Scale (base 4px)

| Token | Value | Use |
|-------|-------|-----|
| `xs` | 4px | Micro gaps, icon insets |
| `sm` | 8px | Tight element spacing |
| `md` | 16px | Standard padding, component gaps |
| `lg` | 32px | Section padding, card padding (web) |
| `xl` | 64px | Section vertical spacing |
| `2xl` | 128px | Page-level vertical rhythm |

### Notes
- App uses intermediate values 12px and 20px freely between `sm` and `md`/`lg`. These are acceptable in SwiftUI where native density demands finer control.
- Web should use CSS variables (`--space-xs` through `--space-2xl`).
- **Hardcoded values to review (web):** `6px`, `14px`, `10px` padding in window bars and buttons should migrate to token combinations or documented exceptions.

---

## Corner Radius

### Unified Scale

| Token | Value | Use |
|-------|-------|-----|
| `sm` | 6px | Tags, small elements, HarmonicFlow bars |
| `md` | 12px | Cards, windows, containers, popups |
| `lg` | 20px | Hero sections, large containers |
| `pill` | 100px | Buttons (web), toggles |

### Alignment Decision: Buttons
- **Web:** Pill buttons (100px radius) for all interactive buttons.
- **App:** Currently uses 8-10px radius.
- **Recommendation:** Align app buttons to pill style for brand consistency, or define platform exception explicitly.

### Hardcoded values to review (web)
- `3px`, `4px`, `5px`, `2px`, `1px`, `1.5px` appear in mock UI elements and keyboard caps. These are acceptable for decorative/illustration elements only.

---

## Color

### Brand Palette

| Token | Light | Dark | Use |
|-------|-------|------|-----|
| `yisi-purple` | #555386 | #9D9AC6 | Primary brand, accents |
| `yisi-deep` | #413F6B | #6A6896 | Gradient stop, emphasis |
| `yisi-light` | #7A78AD | #B0AED6 | Secondary accent |
| `yisi-mist` | #EBEAF5 | #2A2836 | Tinted backgrounds |
| `selection` | rgba(85,83,134,0.18) | rgba(157,154,198,0.18) | Text selection, focus rings |

### Surface Palette

| Token | Light | Dark |
|-------|-------|------|
| `bg` | #fafafa | #0a0a0a |
| `bg-elevated` | #ffffff | #141414 |
| `glass-bg` | rgba(255,255,255,0.6) | rgba(20,20,20,0.6) |
| `glass-border` | rgba(255,255,255,0.25) | rgba(255,255,255,0.08) |

### Text Palette

| Token | Light | Dark |
|-------|-------|------|
| `text-primary` | #1a1a1a | #f0f0f0 |
| `text-secondary` | #6b6b6b | #999999 |
| `text-tertiary` | #9e9e9e | #666666 |

### Border Palette

| Token | Light | Dark |
|-------|-------|------|
| `border` | rgba(0,0,0,0.08) | rgba(255,255,255,0.08) |
| `border-hover` | rgba(0,0,0,0.15) | rgba(255,255,255,0.15) |

### App-Specific Colors

| Token | Light | Dark | Use |
|-------|-------|------|-----|
| `ink-main` | #1F1E2E | #E6E5EB | Primary text |
| `glass-menu` | white/0.65 | #1A1A24/0.65 | Menu panels |
| `glass-card` | white/0.85 | #252433/0.85 | Card surfaces |

### Gradient
- App icon: `linear-gradient(135deg, #555386, #474575)`

---

## Typography

### App (SwiftUI)

| Role | Size | Weight | Design |
|------|------|--------|--------|
| Hero | 64pt | ultraLight | default |
| H1 | 30pt | light | serif |
| H2 | 22pt | medium | serif |
| H3 | 16pt | light | serif |
| Body | 13-14pt | medium | serif |
| Label | 12pt | medium | serif |
| Small | 11pt | medium | serif |
| Micro | 10pt | medium | serif |

**Dominant weights:** .light (89x), .medium (68x). Heavy weights are near-absent.

### Web (CSS)

The website is one column on warm paper (#ecebe5) with film grain; Yisi purple appears only in selections, pressed
keys and the Yisi button. Each feature (translation, preset mode, custom mode, vision) is a section that scrolls normally: a caption
and keycaps, and a macro shot of a tilted screen with a shallow, pointer-following depth of field
(`web/src/macro/Macro.tsx`). On desktop each section fills the viewport and the caption sits over the lower left;
on phones the caption sits above a flat crop. Inside the crop everything shares one
scale (u = 1 pt), so the Yisi window keeps its real 600 × 330 pt size relative to the text, after
`Yisi/UI/Translation/TranslationView.swift`. Each section plays when it scrolls into view: the I-beam selects,
the keys press, the window opens with HarmonicFlow and then the result. Copy is plain description, following the product logic of the original site; after the four sections come
"Yisi has no dialog box" (select → present) and the three principles (free, open source, private).

| Role | Size | Weight | Family |
|------|------|--------|--------|
| Headline | clamp(30px, 2.9vw, 44px) | 500, wdth 90 (zh 600) | Archivo / Noto Serif SC |
| Body | 14-15px | 400 | Archivo |
| Labels, chapter numbers | 12px | 400, wdth 80, tnum | Archivo |
| Wordmark | 15px | 500, wdth 125 | Archivo |

**Letter spacing:** -0.02em for headings, 0.06-0.1em for uppercase labels.
**Line height:** 1.6-1.8 for body text, 1.2-1.3 for headlines.

---

## Depth Strategy: Hybrid

Borders establish structure. Shadows appear on interaction and elevation.

### Borders (primary structure)

| Context | App | Web |
|---------|-----|-----|
| Card/container | 0.5pt, Color.primary.opacity(0.05-0.1) | 1px solid rgba(0,0,0,0.08) |
| Hover state | opacity increases to 0.1-0.2 | border darkens to 0.15 |
| Divider | Divider().opacity(0.3-0.5) | 1px solid var(--color-border) |

### Shadows (interaction + elevation)

| Context | App | Web |
|---------|-----|-----|
| Resting card | none | none |
| Hover | radius 2-4, opacity 0.1 | 0 8px 32px rgba(0,0,0,0.06) |
| Popup/modal | radius 8-20, opacity 0.1-0.2 | 0 12px 40px rgba(0,0,0,0.06) |
| Window | radius 20, opacity 0.2 | 0 4px 20px rgba(0,0,0,0.04) |

---

## Component Patterns

### Buttons

**Web (pill style):**

| Variant | Padding | Radius | Background | Border |
|---------|---------|--------|------------|--------|
| Primary | 14px 32px | 100px | text-primary | none |
| Ghost | 14px 32px | 100px | bg-elevated | 1px solid border |
| Small | 6px 16px | 100px | text-primary | none |
| Language | 6px 14px | 100px | transparent | 1px solid border |

**App:**

| Variant | Height | Padding | Radius | Background |
|---------|--------|---------|--------|------------|
| Primary | 42px | 16px h / 8px v | 10px | AppColors.primary |
| Outlined | 42px | 16px h / 8px v | 10px | clear + stroke |
| Small | 28px | compact | 8px | AppColors.primary |
| Icon | 24px | none | 6px | varies |

**Hover behavior:**
- App: scaleEffect(1.02-1.1), spring animation
- Web: translateY(-1px), shadow appears, 0.2s ease

### Cards

| Property | App | Web |
|----------|-----|-----|
| Radius | 12px | 12px (var(--radius-md)) |
| Border | 0.5pt, opacity 0.05 | 1px, rgba(0,0,0,0.08) |
| Padding | 16px | 32px (var(--space-lg)) |
| Hover bg | Color.primary.opacity(0.02) | none (shadow appears) |
