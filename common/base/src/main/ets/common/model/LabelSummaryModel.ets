export interface LabelSummaryModel {
  labelName: string;
  totalMinutes: number;
  labelColor: ResourceColor; // 权威的纯色，从事项中继承而来
}