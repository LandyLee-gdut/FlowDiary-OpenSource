import { MatterItemModel, MatterStatus } from 'base';

export function createTodayUserGuideMatterItems(): MatterItemModel[] {
  const mockData: MatterItemModel[] = [
    new MatterItemModel({
      id: 'guide-activity-recording',
      title: '写项目文档',
      label: '工作',
      labelColor: $r('app.color.data_viz_1'),
      status: MatterStatus.RECORDING,
      durationInMilliseconds: 25 * 60 * 1000,
    }),

    new MatterItemModel(    {
      id: 'guide-activity-paused',
      title: '健身房锻炼',
      label: '运动',
      labelColor: $r('app.color.data_viz_5'),
      status: MatterStatus.PAUSED,
      durationInMilliseconds: 45 * 60 * 1000,
    }),

    new MatterItemModel(    {
      id: 'guide-activity-todo',
      title: '学习 ArkTS 新特性',
      label: '学习',
      labelColor: $r('app.color.data_viz_3'),
      status: MatterStatus.TODO,
      durationInMilliseconds: 0,
    })


  ];

  return MatterItemModel.ensureList(mockData);
}

