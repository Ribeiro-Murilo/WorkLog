import { describe, expect, it } from "vitest";
import {
  WINDOWS_NOTCH_METRICS,
  buildNotchSvgPath,
  computeNotchRects,
  pointInRect,
  shouldExpandNotch
} from "../src/shared/notchGeometry";

describe("notchGeometry", () => {
  it("mantém a barrinha colapsada compacta horizontalmente em relação ao painel expandido", () => {
    expect(WINDOWS_NOTCH_METRICS.collapsedIdleTotalWidth).toBe(112);
    expect(WINDOWS_NOTCH_METRICS.collapsedRunningTotalWidth).toBe(144);
    expect(WINDOWS_NOTCH_METRICS.collapsedIdleTotalWidth).toBeLessThan(
      WINDOWS_NOTCH_METRICS.expandedTotalWidth / 2
    );
  });

  it("centraliza retângulos no topo da tela selecionada", () => {
    const rects = computeNotchRects(
      { x: 1920, y: 0, width: 1920, height: 1080 },
      false,
      360
    );

    expect(rects.windowBounds.y).toBe(0);
    expect(rects.collapsedRect.y).toBe(0);
    expect(rects.collapsedRect.width).toBe(112);
    // Centro do monitor 1920..3840 é 2880 -> collapsed x = 2880 - 56 = 2824
    expect(rects.collapsedRect.x).toBe(2824);
    expect(rects.expandedRect.width).toBe(368);
    expect(rects.expandedRect.x).toBe(2880 - 184);
  });

  it("aplica política de hover e fixação sem perda de foco", () => {
    expect(
      shouldExpandNotch({
        isExpanded: false,
        isPinned: false,
        isEditing: false,
        isMenuOpen: false,
        containsExpanded: false,
        containsCollapsed: true
      })
    ).toBe(true);

    expect(
      shouldExpandNotch({
        isExpanded: true,
        isPinned: true,
        isEditing: false,
        isMenuOpen: false,
        containsExpanded: false,
        containsCollapsed: false
      })
    ).toBe(true);

    expect(
      shouldExpandNotch({
        isExpanded: true,
        isPinned: false,
        isEditing: false,
        isMenuOpen: false,
        containsExpanded: false,
        containsCollapsed: false
      })
    ).toBe(false);

    expect(pointInRect({ x: 100, y: 0 }, { x: 90, y: 0, width: 50, height: 20 })).toBe(true);
    expect(pointInRect({ x: 89, y: 0 }, { x: 90, y: 0, width: 50, height: 20 })).toBe(false);
  });

  it("gera SVG path válido com ombros côncavos e cantos arredondados", () => {
    const path = buildNotchSvgPath(112, 18, 9, 8);
    expect(path.startsWith("M 0 0")).toBe(true);
    expect(path.endsWith("Z")).toBe(true);
    expect(buildNotchSvgPath(0, 18, 9, 8)).toBe("");
  });
});
