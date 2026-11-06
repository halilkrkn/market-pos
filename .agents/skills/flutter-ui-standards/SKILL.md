---
name: flutter-ui-standards
description: Enforces POS cashier ergonomics, touch target sizing, high-contrast themes, tabular monospace numerical alignment, and keyboard/barcode focus management for Market Management System (MMS) Flutter UI. Use this skill whenever designing or modifying screens, widgets, or responsive layouts for Windows desktop or mobile.
---

# Flutter UI & POS Ergonomics Skill

This skill enforces professional cashier ergonomics, accessibility (a11y), and responsive layout standards for the **Market Management System (MMS)** project, adapted from `nextlevelbuilder/ui-ux-pro-max-skill`.

---

## 1. Cashier Screen Ergonomics (Touch & Speed)

Retail market cashiers process hundreds of items per hour under high-stress conditions. The UI must be optimized for speed, clarity, and zero mis-taps.

### 1.1. Minimum Touch Targets (Fitts's Law)
- **Primary Action Buttons:** Cash sale, Card sale, Complete, Cancel buttons must have a minimum touch target of **$\ge 48 \times 48\text{ dp}$** (preferably $56\text{ dp}$ on mobile and $64\text{ dp}$ on desktop touchscreens).
- **Cart Quantity Buttons:** Plus (`+`), Minus (`-`), and Delete icons must have generous touch padding (`EdgeInsets.all(12)`), preventing accidental neighbor taps.

### 1.2. Numerical Display & Monospace Alignment
- **Tabular / Monospace Figures:** Prices, quantities, subtotals, and total amounts must use font features with tabular figures (`FontFeature.tabularFigures()`) or a monospace font family.
- **Decimal Alignment:** Cents must align vertically on both desktop and mobile screens to allow instantaneous visual auditing by the cashier.
- **Large Total Display:** The final payable amount must be prominently displayed in high-contrast text at a minimum size of **28sp - 36sp**.

---

## 2. Keyboard & Barcode Scanner Focus Management

On Windows PC, cashiers use hardware USB HID keyboard-wedge scanners:
1. **Always-On Barcode Focus:** The POS screen must maintain an active or easily reclaimable focus node on the barcode input buffer without requiring mouse clicks.
2. **Keybinding Shortcuts:**
   - `F1`: Help / Quick Bread button
   - `F2`: Quantity multiplier
   - `F8`: Hold cart
   - `F9`: Card payment
   - `F10` / `Enter`: Cash payment (opens cash received dialog)
   - `Esc`: Clear / Cancel current prompt

---

## 3. High Contrast & Lighting Adaptability

- **Lighting Conditions:** Retail stores have varied lighting (bright fluorescent tubes, dark counter corners). The theme must support high contrast:
  - Contrast ratio for body text must exceed **4.5:1** (WCAG AA).
  - Contrast ratio for large headers and buttons must exceed **7:1** (WCAG AAA).
- **Anti-AI Slop:** Avoid low-contrast purple gradients, faint grey text on white backgrounds, or unnecessary animations that slow down transaction throughput.

