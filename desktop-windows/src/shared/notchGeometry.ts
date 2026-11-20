/**
 * Geometria do Notch compacto para Windows.
 *
 * No macOS o recorte físico da câmera mede ~210px; no Windows o usuário pediu
 * uma barrinha superior estilo notch menor horizontalmente (112px parada / 144px
 * com timer rodando), mantendo o painel expandido fiel ao DESIGN.md (340px corpo
 * + 2*14px ombros côncavos = 368px).
 */
export const WINDOWS_NOTCH_METRICS = {
  // Colapsado parado / pausado (compacto horizontalmente)
  collapsedIdleBodyWidth: 96,
  collapsedShoulderRadius: 8,
  collapsedIdleTotalWidth: 112, // 96 + 2 * 8
  collapsedIdleHeight: 18,
  collapsedIdleBottomRadius: 9,

  // Colapsado com timer rodando (comporta indicador colorido + tempo compacto dentro do preto opaco)
  collapsedRunningBodyWidth: 128,
  collapsedRunningTotalWidth: 144, // 128 + 2 * 8
  collapsedRunningHeight: 22,
  collapsedRunningBottomRadius: 11,

  // Expandido (fiel ao DESIGN.md)
  expandedContentWidth: 340,
  expandedShoulderRadius: 14,
  expandedTotalWidth: 368, // 340 + 2 * 14
  expandedBottomRadius: 20,
  expandedTopPadding: 10,

  // Janela transparente fixa ao redor do notch (evita flicker de resize no DWM)
  windowWidth: 380,
  defaultWindowHeight: 560
} as const;

export interface Rect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface Point {
  x: number;
  y: number;
}

export interface NotchRects {
  windowBounds: Rect;
  collapsedRect: Rect;
  expandedRect: Rect;
}

export function computeNotchRects(
  displayBounds: Rect,
  isRunning: boolean,
  measuredExpandedHeight: number
): NotchRects {
  const windowWidth = Math.min(WINDOWS_NOTCH_METRICS.windowWidth, displayBounds.width);
  const windowHeight = Math.min(WINDOWS_NOTCH_METRICS.defaultWindowHeight, displayBounds.height);
  const windowX = Math.round(displayBounds.x + (displayBounds.width - windowWidth) / 2);
  const windowY = Math.round(displayBounds.y);

  const collapsedWidth = isRunning
    ? WINDOWS_NOTCH_METRICS.collapsedRunningTotalWidth
    : WINDOWS_NOTCH_METRICS.collapsedIdleTotalWidth;
  const collapsedHeight = isRunning
    ? WINDOWS_NOTCH_METRICS.collapsedRunningHeight
    : WINDOWS_NOTCH_METRICS.collapsedIdleHeight;

  const centerX = displayBounds.x + displayBounds.width / 2;
  const collapsedRect: Rect = {
    x: Math.round(centerX - collapsedWidth / 2),
    y: windowY,
    width: collapsedWidth,
    height: collapsedHeight
  };

  const expandedHeight = Math.min(
    Math.max(120, Math.ceil(measuredExpandedHeight)),
    windowHeight
  );
  const expandedWidth = Math.min(WINDOWS_NOTCH_METRICS.expandedTotalWidth, windowWidth);
  const expandedRect: Rect = {
    x: Math.round(centerX - expandedWidth / 2),
    y: windowY,
    width: expandedWidth,
    height: expandedHeight
  };

  return {
    windowBounds: {
      x: windowX,
      y: windowY,
      width: windowWidth,
      height: windowHeight
    },
    collapsedRect,
    expandedRect
  };
}

export function pointInRect(point: Point, rect: Rect): boolean {
  return (
    point.x >= rect.x &&
    point.x <= rect.x + rect.width &&
    point.y >= rect.y &&
    point.y <= rect.y + rect.height
  );
}

export interface NotchHoverInput {
  isExpanded: boolean;
  isPinned: boolean;
  isEditing: boolean;
  isMenuOpen: boolean;
  containsExpanded: boolean;
  containsCollapsed: boolean;
}

export function shouldExpandNotch(input: NotchHoverInput): boolean {
  return (
    input.containsCollapsed ||
    (input.isExpanded &&
      (input.isPinned || input.isEditing || input.isMenuOpen || input.containsExpanded))
  );
}

/**
 * Port exato de `NotchShape.swift`:
 * curvas côncavas superiores (ombros) + cantos inferiores arredondados usando
 * aproximação cúbica de quarto de círculo `k = 0.5522847498`.
 */
export function buildNotchSvgPath(
  width: number,
  height: number,
  cornerRadius: number,
  shoulderRadius: number
): string {
  if (!(width > 0) || !(height > 0)) return "";
  const shoulder = Math.min(Math.max(0, shoulderRadius), width / 4, height / 2);
  const radius = Math.min(
    Math.max(0, cornerRadius),
    (width - 2 * shoulder) / 2,
    (height - shoulder) / 2
  );
  const left = shoulder;
  const right = width - shoulder;
  const k = 0.5522847498;
  const f = (n: number) => Number(n.toFixed(3));

  return [
    `M 0 0`,
    `L ${f(width)} 0`,
    `C ${f(width - shoulder * k)} 0 ${f(right)} ${f(shoulder * (1 - k))} ${f(right)} ${f(shoulder)}`,
    `L ${f(right)} ${f(height - radius)}`,
    `C ${f(right)} ${f(height - radius * (1 - k))} ${f(right - radius * (1 - k))} ${f(height)} ${f(right - radius)} ${f(height)}`,
    `L ${f(left + radius)} ${f(height)}`,
    `C ${f(left + radius * (1 - k))} ${f(height)} ${f(left)} ${f(height - radius * (1 - k))} ${f(left)} ${f(height - radius)}`,
    `L ${f(left)} ${f(shoulder)}`,
    `C ${f(left)} ${f(shoulder * (1 - k))} ${f(shoulder * k)} 0 0 0`,
    `Z`
  ].join(" ");
}
