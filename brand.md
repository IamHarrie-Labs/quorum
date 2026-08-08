# Quorum — Brand

**Status:** active
**Palette:** Chamber Gold
**Derived from:** the Quorum logomark (deep forest green field, antique gold mark and wordmark)
**Vibe:** institutional · premium · serious

Quorum is a securities issuance protocol that enforces legal holder limits on-chain. The brand
should read like a place where records are kept, not like a DeFi app. Deep green and gold is
parliament, ledger, seal — which is exactly the register we want.

---

## Seeds

| Role | OKLCH | Hex | Source |
|---|---|---|---|
| `bg-base` | `oklch(0.28 0.070 152)` | `#04351A` | logo field, one step deeper |
| `bg-elevated` | `oklch(0.34 0.075 152)` | `#063F20` | logo field as-is — cards sit at logo green |
| `primary` | `oklch(0.72 0.090 78)` | `#C69C58` | logo gold |
| `primary-soft` | `oklch(0.60 0.075 78)` | `#A07C42` | gold, dimmed for borders/hover |
| `fg-base` | `oklch(0.95 0.010 90)` | `#F5F2EC` | warm off-white, never pure #FFF |

Dark is the primary mode — it matches the logo and it's what the demo records in. Light mode
exists for the docs pages and for anyone printing an audit export.

---

## shadcn tokens

### Dark (default)

```css
.dark {
  --background:            oklch(0.28 0.070 152);
  --foreground:            oklch(0.95 0.010 90);
  --card:                  oklch(0.34 0.075 152);
  --card-foreground:       oklch(0.95 0.010 90);
  --popover:               oklch(0.31 0.072 152);
  --popover-foreground:    oklch(0.95 0.010 90);
  --primary:               oklch(0.72 0.090 78);
  --primary-foreground:    oklch(0.24 0.060 152);
  --secondary:             oklch(0.38 0.060 152);
  --secondary-foreground:  oklch(0.95 0.010 90);
  --muted:                 oklch(0.36 0.045 152);
  --muted-foreground:      oklch(0.75 0.020 100);
  --accent:                oklch(0.60 0.075 78);
  --accent-foreground:     oklch(0.95 0.010 90);
  --destructive:           oklch(0.60 0.200 25);
  --destructive-foreground:oklch(0.97 0.010 90);
  --border:                oklch(0.40 0.050 152);
  --input:                 oklch(0.40 0.050 152);
  --ring:                  oklch(0.72 0.090 78);
}
```

### Light

```css
:root {
  --background:            oklch(0.98 0.008 95);
  --foreground:            oklch(0.28 0.070 152);
  --card:                  oklch(1.00 0.000 0);
  --card-foreground:       oklch(0.28 0.070 152);
  --popover:               oklch(1.00 0.000 0);
  --popover-foreground:    oklch(0.28 0.070 152);
  --primary:               oklch(0.34 0.075 152);
  --primary-foreground:    oklch(0.98 0.008 95);
  --secondary:             oklch(0.95 0.012 95);
  --secondary-foreground:  oklch(0.28 0.070 152);
  --muted:                 oklch(0.95 0.012 95);
  --muted-foreground:      oklch(0.48 0.030 140);
  --accent:                oklch(0.52 0.100 72);
  --accent-foreground:     oklch(0.98 0.008 95);
  --destructive:           oklch(0.52 0.190 25);
  --destructive-foreground:oklch(0.98 0.008 95);
  --border:                oklch(0.90 0.015 95);
  --input:                 oklch(0.90 0.015 95);
  --ring:                  oklch(0.52 0.100 72);
}
```

Note the deliberate inversion: in dark mode gold is `primary`, in light mode green is `primary`
and gold drops to `accent`. Gold at logo brightness fails AA on a light background, and darkening
it enough to pass turns it muddy. Same two colours, emphasis swapped.

### Contrast (WCAG AA verified)

| Pair | Ratio | Result |
|---|---|---|
| `foreground` on `background` (dark) | ~15.1:1 | AA / AAA |
| `primary` gold on `background` (dark) | ~5.1:1 | AA |
| `primary-foreground` on `primary` (dark) | ~5.1:1 | AA |
| `muted-foreground` on `background` (dark) | ~6.3:1 | AA |
| `foreground` on `background` (light) | ~14.8:1 | AA / AAA |
| `accent` on `background` (light) | ~5.0:1 | AA |

---

## Status colours — read this before building the dashboard

The brand green is the *background*. That breaks the usual green-means-approved convention, so
status colours need to be chosen against the brand, not from a default palette.

```css
--status-approved: oklch(0.75 0.150 155);  /* #56C486 — mint, clearly lighter than brand green */
--status-refused:  oklch(0.62 0.200 25);   /* #D9503F — brick red, warm enough to sit with gold */
--status-pending:  oklch(0.78 0.140 70);   /* #E3A542 — amber, distinct from primary gold */
--seat-filled:     oklch(0.72 0.090 78);   /* primary gold — a taken seat is gold */
--seat-open:       oklch(0.40 0.050 152);  /* border green — an open seat is an empty outline */
```

Rules:
- Never signal "approved" with the brand green. It disappears into the page.
- A filled seat is solid gold, an open seat is a hollow outline. That reads at a glance and it's
  the single most important visual in the product.
- Refusal is red, and it is the only place red appears anywhere in the app. Don't spend it.

---

## Typography

The logo wordmark is a high-contrast display serif with a swashed Q. Closest free match is
**Cormorant Garamond**.

| Role | Font | Use |
|---|---|---|
| Display | Cormorant Garamond (600) | Landing hero, section titles, the big seat count |
| UI sans | Inter | Everything else — labels, buttons, tables, body |
| Mono | JetBrains Mono | Tx hashes, wallet addresses, person IDs, rule pack YAML |

**Do not set the dashboard in serif.** The logo font is right for the landing page and for one or
two hero numbers, and wrong for dense tabular compliance data. The split is:

- Landing page — serif leads, sans supports
- Dashboard — sans leads, serif appears once (the seat counter headline), mono for anything
  hex or machine-generated
- Docs — sans body, mono code blocks, serif page titles only

Every hash and address goes in mono with `font-variant-numeric: tabular-nums`. Numbers that
change live (seat counts, percentages) also get `tabular-nums` so they don't jitter on update.

```tsx
// app/layout.tsx
import { Cormorant_Garamond, Inter, JetBrains_Mono } from "next/font/google";

const serif = Cormorant_Garamond({
  subsets: ["latin"], weight: ["500","600","700"], variable: "--font-serif",
});
const sans  = Inter({ subsets: ["latin"], variable: "--font-sans" });
const mono  = JetBrains_Mono({ subsets: ["latin"], variable: "--font-mono" });
```

```css
@theme inline {
  --font-serif: var(--font-serif);
  --font-sans:  var(--font-sans);
  --font-mono:  var(--font-mono);
}
```

---

## Gradients

Two, both restrained. This brand should not look like it has a gradient.

```css
--gradient-bg: radial-gradient(
  120% 80% at 50% 0%,
  oklch(0.34 0.075 152) 0%,
  oklch(0.28 0.070 152) 55%
);

--gradient-seal: linear-gradient(
  135deg,
  oklch(0.78 0.085 82) 0%,
  oklch(0.66 0.090 72) 100%
);
```

`--gradient-bg` is a barely-there lift behind the landing hero. `--gradient-seal` is for the gold
mark and nothing else — think foil stamp, not button fill. Buttons use flat `--primary`.

---

## Tone and voice

Write like a clerk of records, not like a startup. The product's whole claim is that it is exact,
so the copy has to be exact too. Say "50 persons in any 12-month period," not "compliance made
easy." Numbers over adjectives, always.

Refusals are the most important copy in the app and they are not error messages. When a transfer
is blocked, nothing has gone wrong — the system did its job. The tone is a registrar declining
politely and telling you precisely why: which rule, which threshold, what the current count is.
Never "Access denied." Never red-alert language. The person being refused is not at fault.

Be honest about limits. The one place we admit a gap (Singapore counts offerees, we count
holders) is a feature of the voice, not a weakness in it. Institutions trust the party that
volunteers the caveat.

---

## Dos and don'ts

**Do**
- Keep gold scarce. It marks filled seats, primary actions, and the logo. That's the whole budget.
- Use the outline-vs-filled seat metaphor everywhere a count appears.
- Set every on-chain value in mono and make it a link to the block explorer.
- Let the dark green breathe. Generous spacing reads as institutional; density reads as a trading terminal.

**Don't**
- Don't use serif for anything you'd scan rather than read.
- Don't add a second accent colour. Green, gold, and three status colours is the entire system.
- Don't use glassmorphism, neon glows, or purple. Nothing in this brand should look like 2021 DeFi.
- Don't animate the seat counter with a slot-machine roll. It should tick, once, like a ledger entry.
