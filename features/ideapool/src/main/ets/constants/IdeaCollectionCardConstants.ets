export class IdeaCollectionCardConstants {
  static readonly COVER_IMAGE_SCALE: number = 1.1;
  static readonly COVER_IMAGE_OFFSET_Y: string = '-5vp';
  static readonly COVER_PROGRESSIVE_BLUR_RADIUS: number = 24;
  static readonly COVER_PROGRESSIVE_BLUR_STOPS: Array<[number, number]> = [
    [0, 0],
    [0, 0.5],
    [0.5, 0.72],
    [0.85, 0.88],
    [1, 1]
  ];
}
