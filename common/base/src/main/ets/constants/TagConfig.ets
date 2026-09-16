import { AppGradients } from "./Color";
import { AppColors } from "./Color";

// 定义一个接口来描述标签的视觉属性
export interface TagVisuals {
  solid: ResourceColor;
  gradient: LinearGradient;
}

// 创建一个Map，作为标签名到视觉配置的唯一映射
// 这就像是你数据库中的 `tag` 表
export const TagConfig = new Map<string, TagVisuals>([
  [
    '工作', {
    solid: AppGradients.DATA_PANEL_COLORS[0],     // 蓝色
    gradient: AppGradients.DATA_PANEL_GRADIENTS[0]
  }
  ],
  [
    '健康', {
    solid: AppGradients.DATA_PANEL_COLORS[1],     // 黄色
    gradient: AppGradients.DATA_PANEL_GRADIENTS[1]
  }
  ],
  [
    '学习', {
    solid: AppGradients.DATA_PANEL_COLORS[2],     // 薄荷青
    gradient: AppGradients.DATA_PANEL_GRADIENTS[2]
  }
  ],
  [
    '生活', {
    solid: AppGradients.DATA_PANEL_COLORS[3],     // 紫罗兰
    gradient: AppGradients.DATA_PANEL_GRADIENTS[3]
  }
  ],
// 你可以在这里为所有可能的标签预定义颜色
]);

export const newTagColorOptions: string[] = [
  AppColors.DATA_VIZ_7, AppColors.DATA_VIZ_8, AppColors.DATA_VIZ_9,
  AppColors.DATA_VIZ_10, AppColors.DATA_VIZ_11, AppColors.DATA_VIZ_12,
]

// 提供一个默认颜色，以防遇到未配置的标签
export const DefaultTagVisuals: TagVisuals = {
  solid: AppGradients.DATA_PANEL_COLORS[4], // 珊瑚色
  gradient: AppGradients.DATA_PANEL_GRADIENTS[4]
}