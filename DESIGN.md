---
name: WorkLog Notch
description: Native macOS session controls joined to the physical screen edge.
colors:
  panel-black: "#000000"
  primary-white: "#FFFFFF"
  secondary-gray: "#A5A7AE"
  control-fill: "rgba(255, 255, 255, 0.065)"
  divider: "rgba(255, 255, 255, 0.10)"
  prominent-fill: "rgb(91%, 91%, 91%)"
  project-teal: "rgb(22%, 80%, 81%)"
  project-periwinkle: "rgb(48%, 53%, 100%)"
  project-orange: "rgb(100%, 63%, 29%)"
  project-green: "rgb(56%, 83%, 37%)"
  project-pink: "rgb(89%, 52%, 72%)"
  project-lilac: "rgb(78%, 66%, 96%)"
typography:
  display:
    fontFamily: "SF Mono (SwiftUI system monospaced design)"
    fontSize: "42pt"
    fontWeight: 400
  title:
    fontFamily: "SF (SwiftUI system)"
    fontSize: "16pt"
    fontWeight: 600
  headline:
    fontFamily: "SF (SwiftUI system)"
    fontSize: "14pt"
    fontWeight: 600
  action:
    fontFamily: "SF (SwiftUI system)"
    fontSize: "13pt"
    fontWeight: 500
  body:
    fontFamily: "SF (SwiftUI system)"
    fontSize: "12pt"
    fontWeight: 400
  detail:
    fontFamily: "SF (SwiftUI system)"
    fontSize: "11pt"
    fontWeight: 400
  label:
    fontFamily: "SF (SwiftUI system)"
    fontSize: "10pt"
    fontWeight: 500
    letterSpacing: "0.4pt"
rounded:
  control: "8pt"
  row: "6pt"
  panel-bottom: "20pt"
spacing:
  panel-inset: "16pt"
  section-gap: "14pt"
  content-gap: "12pt"
  action-gap: "10pt"
  field-gap: "8pt"
  detail-gap: "3pt"
components:
  button-primary:
    backgroundColor: "{colors.prominent-fill}"
    textColor: "{colors.panel-black}"
    typography: "{typography.action}"
    rounded: "{rounded.control}"
    height: "36pt"
  button-secondary:
    backgroundColor: "{colors.control-fill}"
    textColor: "{colors.primary-white}"
    typography: "{typography.action}"
    rounded: "{rounded.control}"
    height: "36pt"
  search:
    backgroundColor: "{colors.control-fill}"
    textColor: "{colors.primary-white}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    height: "34pt"
  project-row:
    textColor: "{colors.primary-white}"
    typography: "{typography.action}"
    rounded: "{rounded.row}"
    height: "46pt"
  timer:
    textColor: "{colors.primary-white}"
    typography: "{typography.display}"
  panel:
    backgroundColor: "{colors.panel-black}"
    textColor: "{colors.primary-white}"
    padding: "{spacing.panel-inset}"
    width: "340pt"
---

# Design System: WorkLog Notch

## Overview

**Creative North Star: "The Camera-Integrated Session Panel"**

The approved notch world joins an opaque black session panel to the physical screen edge. Restrained gray text, native SF typography and small project identifiers keep the session and its controls readable in a compact surface.

This document governs the notch panel only. Dashboard, other application screens and the menu bar retain their incumbent UI; these rules do not mandate an application-wide rebrand. Measurements describe native SwiftUI/AppKit points, not CSS implementation. The source is authoritative; the sidecar includes illustrative browser translations for the design panel.

**Key Characteristics:**
- Opaque camera-integrated silhouette with concave shoulders.
- A large monospaced session timer and clear primary action.
- Compact project rows, bounded scrolling and a visible utility footer.

## Colors

The palette is neutral and hardware-adjacent; project identifiers supply the only recurring chromatic accents. Frontmatter records the source color components without rounding the six project colors to hex.

### Primary

- **Primary white** carries the timer, project names and primary text.
- **Prominent fill** makes the session’s main action a light control with black text.

### Neutral

- **Panel black** joins the expanded silhouette to the camera area.
- **Secondary gray** carries client names, placeholders, totals captions and footer utilities.
- **Control fill** provides quiet separation for buttons and search.
- **Divider** separates major groups and project rows.

The six project colors are deterministic identifiers, selected from UUID bytes in `NotchPanelStyle.projectColor`; they are not status colors or interchangeable brand accents.

**The Session Hierarchy Rule.** Reserve the prominent light button for the current session’s main action; project colors identify projects.

## Typography

**Display Font:** native SF monospaced system design. **Body Font:** native SF system design. SwiftUI selects the platform face; no bundled font or web fallback is part of the application.

The timer is the dominant reading target. Names and controls use modest weight changes rather than decorative display typography. Frontmatter owns the reusable type ramp. Line heights remain native; the code does not declare a custom proportional scale.

- **Display:** session elapsed time, regular monospaced digits, centered.
- **Title:** current project and idle-state heading.
- **Headline:** WorkLog identity in the header.
- **Action:** session buttons and project-row names.
- **Body:** clients, search, daily total and footer text; the total uses medium weight and monospaced digits.
- **Detail:** project-row clients and inline error copy.

## Layout

A single vertical column uses the panel inset and section gap from frontmatter. `NotchPanelMetrics` defines a content body (340pt), concave shoulder allowance (14pt each), and complete expanded window (368pt). The body width includes its internal padding. Smaller local gaps follow content grouping rather than a fabricated global grid.

**The Camera Clearance Rule.** Keep the expanded content below the physical camera height; the black silhouette begins at the physical screen edge.

The camera clearance is the selected display’s measured `notchHeight`, not a fixed decorative spacer. Height follows measured content and is capped to the display height. There are no web or mobile breakpoints.

Project rows occupy their frontmatter height; the list’s viewport is the smaller of row count times row height plus inter-row separators and (144pt). Daily total and footer remain outside that scroll view. Names and clients are single-line and expose full text through native help. Empty, no-result and idle messages wrap naturally.

## Elevation & Depth

No panel shadow is used: the AppKit panel explicitly disables it. Opaque black, subtle control fills, outlines and separators establish hierarchy without blur or floating cards. Section dividers are (1pt); project-row hairlines are (1pt), inset from the leading edge (30pt) and omitted after the last row.

Expansion and collapse use SwiftUI ease-in-out (0.25s). This is a native transition, not evidence of a CSS easing curve.

## Shapes

The signature silhouette uses top concave shoulders and softly rounded bottom corners; the shoulder allowance belongs inside the complete window. `NotchShape` supplies cubic quarter-circle approximations, with radius clamping for small geometry. The expanded bottom radius comes from frontmatter; collapsed geometry follows the physical notch with the shape’s native default bottom radius (12pt).

Controls and row hover areas use their separate frontmatter radii. Project identifiers are small circles (12pt); row play controls have circular outlines within (26pt) frames. Native SF Symbols provide functional icons.

## Components

### Buttons

The main session action is light and full-width within available space. In a running session it shares a row with an outlined secondary stop action of fixed width (114pt), separated by the action gap. Paused sessions show one prominent resume action.

The primary pressed fill uses native grayscale (0.72); all session buttons reduce opacity to (0.85) when pressed. Secondary buttons have a white outline at (20% opacity). ButtonStyle does not define a custom hover fill or focus ring; native semantics remain intact.

### Inputs / Fields

Search uses the body type, control fill and control radius. It has horizontal inset (11pt), a magnifying-glass SF Symbol and a conditional clear action. Its white border shifts from (8% opacity) to (50% opacity) while focused. Escape clears a query, then releases focus when already empty.

### Navigation

The utility footer keeps Dashboard access, settings and the more-options menu visible. It uses secondary gray and plain native controls with (26pt) minimum action frames. The header pin has a (28pt by 24pt) target and turns white when pinned.

### Project Rows

Rows combine an identity circle, name, optional client and optional favorite SF Symbol with an outlined play affordance. Horizontal inset is (6pt), circle-to-copy spacing uses the content gap, and client-to-name spacing uses the detail gap. Hover adds white at (7% opacity) behind the row and strengthens the play outline from (30% opacity) to (60% opacity). Hairlines preserve list rhythm without turning each project into a card.

### Session and Empty States

The session timer stays centered with vertical inset (3pt). Running and paused states share the same visual hierarchy; idle state replaces the timer and controls with concise native copy. An inline error, when present, uses warm source color `Color(red: 1, green: 0.69, blue: 0.62)` and native error semantics; this one-off is not promoted into a reusable accent token.

The collapsed state preserves the opaque hardware-width region and a small white indicator at (60% opacity), while its trailing region is transparent so it does not cover the menu bar.

## Do's and Don'ts

### Do:
- **Do** preserve physical camera clearance and the complete concave shoulders.
- **Do** keep the daily total and footer outside the bounded project scroll area.
- **Do** use the native system font and monospaced timer design in this macOS surface.
- **Do** preserve project identity colors consistently across launches and devices.

### Don't:
- **Don’t** replace the opaque camera-integrated background with translucent material.
- **Don’t** stretch the panel to accommodate long project names; truncate names and expose their full value through help.
- **Don’t** apply this notch-only system to other application screens without a separate design decision.

Uppercase functional state and list labels (10pt medium, tracking 0.4pt) preserve the hierarchy explicitly approved by the user. Native SF typography is the platform choice for this macOS surface.

Evidence: `WorkLog/Notch/NotchPanelStyle.swift`, `NotchPanelView.swift`, `NotchShape.swift`, `NotchContentView.swift`, and the shadow/window configuration in `NotchWindowController.swift`; scope and approved visual direction are recorded in `PRODUCT.md` and `.impeccable/surfaces/worklog-notch-notchpanelview-swift.md`. The approved raster is `.impeccable/mocks/notch-approved.png`. This record makes no claim that a browser detector or pixel-diff gate passed.
