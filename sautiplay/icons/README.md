# SautiPlay Audiophile Engine — Minimalist SVG Icon System v2.0

Total Icons Packaged: **103**
Grid System: `24x24`
Stroke Width: `1.75px`
Stroke Color Mode: `currentColor`

## Contents of this .ZIP Archive
- `<category>/<icon-id>.svg`: Individual minimalist SVG files organized by SautiPlay engine category.
- `android-xml/ic_sauti_<icon_id>.xml`: Ready-to-use Android VectorDrawable XML resources.
- `sautiplay-sprite.svg`: Master SVG `<symbol>` sprite sheet.
- `sautiplay-icons.json`: Full JSON catalog with metadata, tags, descriptions, and raw SVG strings.
- `SautiPlayIcon.tsx`: Ready-to-use React / TypeScript component with full type safety.

## Quick Usage

### 1. HTML / Web SVG Sprite
```html
<svg class="w-6 h-6 text-[#FF6B2B]">
  <use href="sautiplay-sprite.svg#sauti-convolver"></use>
</svg>
```

### 2. React / React Native / TypeScript
```tsx
import { SautiPlayIcon } from './SautiPlayIcon';

<SautiPlayIcon name="convolver" size={24} strokeWidth={1.75} className="text-amber-500" />
```

### 3. Android Jetpack Compose / XML
Copy any file from `android-xml/` into `app/src/main/res/drawable/` and reference via `R.drawable.ic_sauti_convolver`.
