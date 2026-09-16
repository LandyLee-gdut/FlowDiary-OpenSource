import { AddNewTagDialog, TagDialogDependencies } from 'base';
import { loadTagsFromDatabase } from '../model/TodayModel';

@CustomDialog
export struct addNewItemDialog {
  private readonly dialogDeps: TagDialogDependencies = {
    refreshTags: () => loadTagsFromDatabase()
  };

  controller: CustomDialogController = new CustomDialogController({
    builder: addNewItemDialog({
      isShow: this.isShow,
      inputActivityName: this.inputActivityName,
      selectedTagIndex: this.selectedTagIndex,
      sheetHeight: this.sheetHeight,
      inputTagName: this.inputTagName,
      selectedLabelIndex: this.selectedLabelIndex
    }),
    autoCancel: true
  });
  @State showFlag: Visibility = Visibility.Visible;
  @Link inputActivityName: string;
  @Link selectedTagIndex: number;
  @Link sheetHeight: number;
  @Link inputTagName: string;
  @Link selectedLabelIndex: number;
  @Link isShow: boolean;

  build() {
    AddNewTagDialog({
      controller: this.controller,
      inputActivityName: this.inputActivityName,
      selectedTagIndex: this.selectedTagIndex,
      sheetHeight: this.sheetHeight,
      inputTagName: this.inputTagName,
      selectedLabelIndex: this.selectedLabelIndex,
      isShow: this.isShow,
      showFlag: this.showFlag,
      dependencies: this.dialogDeps
    });
  }

  cancel() {
    this.showFlag = Visibility.Hidden;
    setTimeout(() => {
      this.controller.close();
    }, 400);
  }
}
