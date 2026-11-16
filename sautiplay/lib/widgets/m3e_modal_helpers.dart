import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

/// Presents an [M3EBottomSheet] whose subtree is wrapped in a transparent
/// [Material] so `material_ui` widgets (e.g., [ActionChip], [ListTile],
/// [InkWell], [TextField]) always find a [Material] ancestor.
Future<T?> showSautiM3EBottomSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool showDragHandle = true,
  bool isDismissible = true,
  bool enableDrag = true,
  M3EBottomSheetValue initialValue = M3EBottomSheetValue.collapsed,
  bool expandToFullScreen = false,
  String? fullScreenTitle,
  M3EBottomSheetController? controller,
  ValueChanged<M3EBottomSheetValue>? onValueChanged,
  Future<bool> Function()? onDismissRequest,
  M3EBottomSheetTheme? theme,
  M3EBottomSheetLabels labels = const M3EBottomSheetLabels(),
  bool useRootNavigator = true,
}) {
  return M3EBottomSheet.show<T>(
    context,
    builder: (sheetContext) => Material(
      type: MaterialType.transparency,
      child: builder(sheetContext),
    ),
    showDragHandle: showDragHandle,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    initialValue: initialValue,
    expandToFullScreen: expandToFullScreen,
    fullScreenTitle: fullScreenTitle,
    controller: controller,
    onValueChanged: onValueChanged,
    onDismissRequest: onDismissRequest,
    theme: theme,
    labels: labels,
    useRootNavigator: useRootNavigator,
  );
}

/// Presents an [M3EDialog] whose subtree is wrapped in a transparent
/// [Material] so `material_ui` widgets inside dialog content or actions
/// always find a [Material] ancestor.
Future<T?> showSautiM3EDialog<T>(
  BuildContext context, {
  required Widget dialog,
  bool barrierDismissible = true,
  bool? resizeToAvoidBottomInset,
  M3EDialogPosition position = M3EDialogPosition.center,
  M3EDialogController? controller,
  Future<bool> Function()? onDismissRequest,
  bool autofocusFirst = true,
}) {
  return M3EDialog.show<T>(
    context,
    dialog: Material(
      type: MaterialType.transparency,
      child: dialog,
    ),
    barrierDismissible: barrierDismissible,
    resizeToAvoidBottomInset: resizeToAvoidBottomInset,
    position: position,
    controller: controller,
    onDismissRequest: onDismissRequest,
    autofocusFirst: autofocusFirst,
  );
}
