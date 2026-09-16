// 数据面板的数据类型
export interface  CircleDataPanelModel {
  duration: number, // duration length of event
  label: string, // label of the event
  color: ResourceColor, // the color of event
  labelID?: number // the id of label
}