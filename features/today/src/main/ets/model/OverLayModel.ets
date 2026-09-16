import { curves } from "@kit.ArkUI";
import { hilog } from "@kit.PerformanceAnalysisKit";
import { hdsEffect } from "@kit.UIDesignKit";
import { JSON } from "@kit.ArkTS";
import { resolvePointLightProfile } from 'base';

export interface Point {
  x: number;
  y: number;
}

/**
 * FanItem的额外数据，用于"直接记录"逻辑
 * 当选中FanItem时，可以直接创建MatterItem并开始记录
 * 活动名称将使用FanItem的label作为名称
 */
export interface DirectRecordData {
  tagId: string | null;      // 标签ID
  autoStart: boolean;        // 是否自动开始记录
}

export class FanItem {
  icon: string;
  label: string;
  id: number;
  // 新增：用于"直接记录"的数据
  directRecordData?: DirectRecordData;

  constructor(icon: string, label: string, id: number, directRecordData?: DirectRecordData) {
    this.icon = icon;
    this.label = label;
    this.id = id;
    this.directRecordData = directRecordData;
  }
}

export interface FanItemTagMetadata {
  id: string;
  name: string;
  color: string;
  lightColor: string;
}

export enum FanActionKind {
  DIRECT_RECORD = 'directRecord',
  VOICE_INPUT = 'voiceInput'
}

export interface FanItemVO {
  icon: string;
  label: string;
  id: number;
  actionKind?: FanActionKind;
  directRecordData?: DirectRecordData;
  tagMeta?: FanItemTagMetadata | null;
}

export interface FanItemTagLookup {
  id: string;
  name: string;
  color: string;
  lightColor: string;
}

export function toFanItemVOs(
  items: Array<FanItem | FanItemVO>,
  tags: FanItemTagLookup[]
): FanItemVO[] {
  if (!items || items.length === 0) {
    return [];
  }

  const tagMap: Map<string, FanItemTagLookup> = new Map(
    (tags ?? []).map((tag: FanItemTagLookup): [string, FanItemTagLookup] => [tag.id, tag])
  );

  return items.map((item: FanItem | FanItemVO): FanItemVO => {
    const directRecordData: DirectRecordData | undefined = item.directRecordData
      ? item.directRecordData
      : undefined;

    const result: FanItemVO = {
      icon: item.icon,
      label: item.label,
      id: item.id,
      directRecordData
    };

    const tagId: string | null = directRecordData?.tagId ?? null;
    if (tagId) {
      const matchedTag: FanItemTagLookup | undefined = tagMap.get(tagId);
      result.tagMeta = matchedTag
        ? {
            id: matchedTag.id,
            name: matchedTag.name,
            color: matchedTag.color,
            lightColor: matchedTag.lightColor
          }
        : null;
    } else {
      result.tagMeta = null;
    }

    return result;
  });
}

export class FanOverlayParams {
  center: Point;
  startAngle: number;
  sweepAngle: number;
  radius: number;
  innerR: number;
  outerR: number;
  items: FanItemVO[];
  layoutPoints: Point[];
  itemOffsets: Point[];
  stackAlignment: Alignment;
  itemMarginBottom: number;
  reverseSectorOrder: boolean;
  onPick: (item: FanItemVO) => void;
  onClose: () => void;
  visible: boolean;

  constructor(
    center: Point,
    startAngle: number,
    sweepAngle: number,
    radius: number,
    innerR: number,
    outerR: number,
    items: FanItemVO[],
    layoutPoints: Point[],
    itemOffsets: Point[],
    stackAlignment: Alignment,
    itemMarginBottom: number,
    reverseSectorOrder: boolean,
    onPick: (item: FanItemVO) => void,
    onClose: () => void,
    visible: boolean = true
  ) {
    this.center = center;
    this.startAngle = startAngle;
    this.sweepAngle = sweepAngle;
    this.radius = radius;
    this.innerR = innerR;
    this.outerR = outerR;
    this.items = items;
    this.layoutPoints = layoutPoints;
    this.itemOffsets = itemOffsets;
    this.stackAlignment = stackAlignment;
    this.itemMarginBottom = itemMarginBottom;
    this.reverseSectorOrder = reverseSectorOrder;
    this.onPick = onPick;
    this.onClose = onClose;
    this.visible = visible;
  }

  // 复制一份参数并切换可见性，用于关闭时先播放出场动画再卸载 overlay
  public withVisible(visible: boolean): FanOverlayParams {
    return new FanOverlayParams(
      this.center,
      this.startAngle,
      this.sweepAngle,
      this.radius,
      this.innerR,
      this.outerR,
      this.items,
      this.layoutPoints,
      this.itemOffsets,
      this.stackAlignment,
      this.itemMarginBottom,
      this.reverseSectorOrder,
      this.onPick,
      this.onClose,
      visible
    );
  }
}

// 上方扇形的默认角度范围（π..2π 为“上半区”，因为 y 向下为正）
// 这里选择从 -π 到 0（规范化后等价于 π..2π），即“上方180°扇形”
export const DEFAULT_START_ANGLE: number = -Math.PI;
export const DEFAULT_SWEEP_ANGLE: number = Math.PI;
export const FAN_ITEM_CONTAINER_SIZE: number = 72;
export const FAN_ITEM_HALF_SIZE: number = FAN_ITEM_CONTAINER_SIZE / 2;
export const FAN_ITEM_VIEW_SIZE: number = 45;
export const FAN_ITEM_ACTIVE_VIEW_SIZE: number = 60;
// 背景模糊半径：与语音输入条一致的清透毛玻璃
const FAN_ITEM_GLASS_BLUR_RADIUS: number = 10;

const TAG = 'OverLayModel'

// 角度归一化到 [0, 2π)
function normalizeAngle(theta: number): number {
  let t = theta;
  while (t < 0) {
    t += 2 * Math.PI;
  }
  while (t >= 2 * Math.PI) {
    t -= 2 * Math.PI;
  }
  return t;
}

// 计算扇形内的扇区索引（返回 -1 表示未命中任何子项或处于取消区）
function computeSectorIndexForPoint(
  center: Point,
  startAngle: number,
  sweepAngle: number,
  itemCount: number,
  innerR: number,
  outerR: number,
  px: number,
  py: number
): number {
  if (itemCount <= 0) {
    return -1;
  }

  const dx: number = px - center.x;
  const dy: number = py - center.y;
  const dist: number = Math.hypot(dx, dy);

  if (dist < innerR) {
    return -1;
  }
  if (outerR > 0 && dist > outerR) {
    return -1;
  }

  let theta: number = Math.atan2(dy, dx);
  theta = normalizeAngle(theta);

  const startNorm: number = normalizeAngle(startAngle);
  let rel: number = theta - startNorm;
  if (rel < 0) {
    rel += 2 * Math.PI;
  }

  if (rel > sweepAngle) {
    return -1;
  }

  const step: number = sweepAngle / Math.max(itemCount, 1);
  const idx: number = Math.min(Math.floor(rel / step), itemCount - 1);
  if (idx < 0 || idx >= itemCount) {
    return -1;
  }
  return idx;
}

export function computeActiveFanSectorIndex(
  globalPoint: Point,
  center: Point | null,
  startAngle: number,
  sweepAngle: number,
  itemCount: number,
  innerRadius: number,
  outerRadius: number,
  reverseSectorOrder: boolean
): number {
  if (!center) {
    return -1;
  }

  const sectorIndex: number = computeSectorIndexForPoint(
    center,
    startAngle,
    sweepAngle,
    itemCount,
    innerRadius,
    outerRadius,
    globalPoint.x,
    globalPoint.y
  );
  if (sectorIndex < 0 || !reverseSectorOrder) {
    return sectorIndex;
  }
  return itemCount - 1 - sectorIndex;
}

// 预设的扇形布局（相对于 Stack 圆心的偏移，单位 px）
export function normalizeDirectRecordData(raw: DirectRecordData): DirectRecordData | undefined {
  if (!raw || typeof raw !== 'object') {
    return undefined;
  }

  const record = raw as DirectRecordData;
  let tagId: string | null = null;
  const rawTagId = record.tagId;
  if (typeof rawTagId === 'string' && rawTagId.trim().length > 0) {
    tagId = rawTagId.trim();
  }

  const rawAutoStart = record.autoStart;
  const autoStart = typeof rawAutoStart === 'boolean' ? rawAutoStart : false;

  return { tagId, autoStart };
}

export function parseSwissKnifeItemsPreference(storedValue: string): FanItem[] {
  const customItems: FanItem[] = [];
  const usedIds: Set<number> = new Set<number>();
  let nextGeneratedId: number = 100;

  const allocateId = (candidate?: number): number => {
    if (typeof candidate === 'number' && !Number.isNaN(candidate) && !usedIds.has(candidate)) {
      usedIds.add(candidate);
      return candidate;
    }

    while (usedIds.has(nextGeneratedId)) {
      nextGeneratedId++;
    }

    const allocated = nextGeneratedId;
    usedIds.add(allocated);
    nextGeneratedId++;
    return allocated;
  };

  if (typeof storedValue === 'string') {
    try {
      const parsed = JSON.parse(storedValue);
      if (Array.isArray(parsed)) {
        parsed.forEach((raw: FanItem) => {
          if (!raw || typeof raw !== 'object') {
            return;
          }

          const record = raw as FanItem;
          const rawLabel = record.label;
          const label = typeof rawLabel === 'string' ? rawLabel.trim() : '';
          if (!label) {
            return;
          }

          const iconValue = record.icon;
          const icon = typeof iconValue === 'string' ? iconValue : '⭐️';
          const candidateId = typeof record.id === 'number' ? record.id : undefined;
          const directRecord = normalizeDirectRecordData(record.directRecordData as DirectRecordData);
          if (!directRecord) {
            return;
          }

          const fanItemId = allocateId(candidateId);
          customItems.push(new FanItem(icon, label, fanItemId, directRecord));
        });
      } else {
        hilog.warn(0x0000, TAG, `[OverLayModel] Preference value is not an array, using empty swiss knife list.`);
      }
    } catch (error) {
      hilog.error(0x0000, TAG, `[OverLayModel] Failed to parse fan items preference: ${JSON.stringify(error)}`);
    }
  } else if (storedValue !== undefined) {
    hilog.warn(0x0000, TAG, `[OverLayModel] Preference value is not a string, using empty swiss knife list.`);
  }

  return customItems;
}

export function computeActiveFanIndex(
  globalPoint: Point,
  center: Point | null,
  layoutPoints: Point[],
  itemCount: number,
  innerRadius: number,
  outerRadius: number
): number {
  if (!center || itemCount <= 0 || layoutPoints.length !== itemCount) {
    return -1;
  }

  const dx: number = globalPoint.x - center.x;
  const dy: number = globalPoint.y - center.y;
  const dist: number = Math.hypot(dx, dy);

  if (dist < innerRadius) {
    return -1;
  }

  if (outerRadius > 0 && dist > outerRadius) {
    return -1;
  }

  let bestIndex: number = -1;
  let bestDistSq: number = Number.POSITIVE_INFINITY;
  const maxHoverDistanceSq: number = FAN_ITEM_CONTAINER_SIZE * FAN_ITEM_CONTAINER_SIZE;

  for (let i: number = 0; i < itemCount; i++) {
    const layoutPoint: Point = layoutPoints[i];
    const itemDx: number = globalPoint.x - layoutPoint.x;
    const itemDy: number = globalPoint.y - layoutPoint.y;
    const distSq: number = itemDx * itemDx + itemDy * itemDy;

    if (distSq < bestDistSq) {
      bestDistSq = distSq;
      bestIndex = i;
    }
  }

  if (bestIndex >= 0 && bestDistSq <= maxHoverDistanceSq) {
    return bestIndex;
  }

  return -1;
}

// 预设的扇形布局（相对于 Stack 圆心的偏移，单位 px）
const HARD_CODED_FAN_LAYOUTS: Record<number, Point[]> = {
  1: [
    { x: 0.0, y: -110.0 }
  ],
  2: [
    { x: -55.0, y: -95.26 },
    { x: 55.0, y: -95.26 }
  ],
  3: [
    { x: -77.78, y: -77.78 },
    { x: 0.0, y: -110.0 },
    { x: 77.78, y: -77.78 }
  ],
  4: [
    { x: -95.26, y: -55.0 },
    { x: -37.62, y: -103.37 },
    { x: 37.62, y: -103.37 },
    { x: 95.26, y: -55.0 }
  ],
  5: [
    { x: -103.92, y: -60.0 },
    { x: -60.0, y: -103.92 },
    { x: 0.0, y: -120.0 },
    { x: 60.0, y: -103.92 },
    { x: 103.92, y: -60.0 }
  ]
};

const DEFAULT_FAN_LAYOUT: Point[] = HARD_CODED_FAN_LAYOUTS[4];

export function computeFanLayout(
  center: Point,
  _startAngle: number,
  _sweepAngle: number,
  _radius: number,
  itemCount: number
): Point[] {
  const positions: Point[] = [];
  if (itemCount <= 0) {
    return positions;
  }

  const sweepAngle: number = Math.max(_sweepAngle, 0);
  const radius: number = Math.max(_radius, 0);
  const startAngle: number = itemCount === 1
    ? _startAngle + sweepAngle / 2
    : _startAngle;
  const step: number = itemCount === 1 ? 0 : sweepAngle / Math.max(itemCount - 1, 1);

  for (let i: number = 0; i < itemCount; i++) {
    const angle: number = startAngle + step * i;
    positions.push({
      x: center.x + radius * Math.cos(angle),
      y: center.y + radius * Math.sin(angle)
    });
  }
  return positions;
}

export function computeFanItemViewPositions(layoutPoints: Point[], fallbackCenter: Point): Point[] {
  if (!layoutPoints || layoutPoints.length === 0) {
    return [];
  }

  return layoutPoints.map((point: Point): Point => ({
    x: (point?.x ?? fallbackCenter.x) - FAN_ITEM_HALF_SIZE,
    y: (point?.y ?? fallbackCenter.y) - FAN_ITEM_HALF_SIZE
  }));
}

export function computeLegacyFanLayout(center: Point, itemCount: number): Point[] {
  const positions: Point[] = [];
  if (itemCount <= 0) {
    return positions;
  }

  const layoutOffsets: Point[] = HARD_CODED_FAN_LAYOUTS[itemCount]
    ? HARD_CODED_FAN_LAYOUTS[itemCount]
    : DEFAULT_FAN_LAYOUT;

  for (let i: number = 0; i < itemCount; i++) {
    const offset: Point = layoutOffsets[Math.min(i, layoutOffsets.length - 1)];
    positions.push({
      x: center.x + offset.x + FAN_ITEM_HALF_SIZE,
      y: center.y + offset.y + FAN_ITEM_HALF_SIZE
    });
  }

  return positions;
}

export function computeLegacyRenderOffsets(itemCount: number): Point[] {
  const layoutOffsets: Point[] = HARD_CODED_FAN_LAYOUTS[itemCount]
    ? HARD_CODED_FAN_LAYOUTS[itemCount]
    : DEFAULT_FAN_LAYOUT;

  return layoutOffsets.map((offset: Point): Point => ({
    x: offset.x,
    y: offset.y + 10
  }));
}

@Component
struct FanOverlayView {
  @Prop params: FanOverlayParams;
  @StorageLink('swissKnifeActiveIndex') activeIndex: number = -1;

  aboutToAppear(): void {
    // 初始化时重置选中索引
    this.activeIndex = -1;
  }

  private resolveFanGlassGradientColors(isActive: boolean): Array<[ResourceColor, number]> {
    return isActive
      ? [
          [$r('app.color.today_fan_glass_active_top'), 0],
          [$r('app.color.today_fan_glass_active_bottom'), 1]
        ]
      : [
          [$r('app.color.today_fan_glass_top'), 0],
          [$r('app.color.today_fan_glass_bottom'), 1]
        ];
  }

  private buildSelectionPointLightEffect(isActive: boolean): VisualEffect {
    const profile = resolvePointLightProfile({
      preset: 'selection',
      color: $r('app.color.immersive_glow_warning'),
      illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER,
      isActive: isActive,
      isDarkTheme: false
    });
    return new hdsEffect.HdsEffectBuilder()
      .pointLight({
        illuminatedType: profile.illuminatedType,
        options: {
          color: profile.color,
          height: profile.height,
          intensity: profile.intensity,
          bloom: profile.bloom
        }
      })
      .pressShadow(isActive ? hdsEffect.PressShadowType.BLEND_WHITE : hdsEffect.PressShadowType.NONE)
      .buildEffect();
  }

  build() {
    Stack({ alignContent: this.params.stackAlignment }) {
        if (this.params.visible) {
          ForEach(this.params.items, (item: FanItemVO, index: number) => {
          Column() {
            Text(item.icon)
              .fontSize(20)
              .textAlign(TextAlign.Center);
          }
          .onClick(() => {
            this.activeIndex = index;
            this.params.onPick(item);
            this.params.onClose();
          })
          .margin({ bottom: this.params.itemMarginBottom })
          .alignItems(HorizontalAlign.Center)
          .justifyContent(FlexAlign.Center)
          .transition(TransitionEffect.asymmetric(
            TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0, y: 0 })).animation({curve: curves.springMotion(), duration: 250, delay: 50 * index}),
            TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0, y: 0 })).animation({curve: Curve.EaseIn, duration: 100})
          ))
          .width(this.activeIndex === index ? FAN_ITEM_ACTIVE_VIEW_SIZE : FAN_ITEM_VIEW_SIZE)
          .height(this.activeIndex === index ? FAN_ITEM_ACTIVE_VIEW_SIZE : FAN_ITEM_VIEW_SIZE)
          .borderRadius('50%')
          .clip(true)
          .backdropBlur(FAN_ITEM_GLASS_BLUR_RADIUS)
          .linearGradient({
            direction: GradientDirection.Bottom,
            colors: this.resolveFanGlassGradientColors(this.activeIndex === index)
          })
          .visualEffect(this.buildSelectionPointLightEffect(this.activeIndex === index))
          .shadow({ radius: 12, color: '#22000000', offsetX: 0, offsetY: 4 })
          .offset({
            x: this.params.itemOffsets[index]?.x ?? 0,
            y: this.params.itemOffsets[index]?.y ?? 0
          })
          .animation({ curve: Curve.Linear, duration: 100})
        }, (item: FanItemVO) => item.id.toString());
        }
    }
    .width('100%')
    .height('100%')
    .gesture(TapGesture()
      .onAction((event) => {
        const finger = event?.fingerList ? event.fingerList[0] : undefined;
        if (!finger) {
          return;
        }
        const globalX = finger.globalX;
        const globalY = finger.globalY;
        if (typeof globalX !== 'number' || typeof globalY !== 'number') {
          return;
        }

        const tappedIndex: number = computeActiveFanSectorIndex(
          { x: globalX, y: globalY },
          this.params.center,
          this.params.startAngle,
          this.params.sweepAngle,
          this.params.items.length,
          this.params.innerR,
          this.params.outerR,
          this.params.reverseSectorOrder
        );

        if (tappedIndex === -1) {
          this.params.onClose();
        }
      })
    )
  }
}

@Builder
export function buildFanOverlay(params: FanOverlayParams) {
  FanOverlayView({ params: params });
}
