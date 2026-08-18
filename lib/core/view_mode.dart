import 'package:flutter/material.dart';

import '../models/session.dart';

class CehViewModeController extends ChangeNotifier {
  bool _viewAsOperator = false;
  bool get viewAsOperator => _viewAsOperator;

  void enableOperatorView() {
    if (_viewAsOperator) return;
    _viewAsOperator = true;
    notifyListeners();
  }

  void returnToAdmin() {
    if (!_viewAsOperator) return;
    _viewAsOperator = false;
    notifyListeners();
  }
}

class CehViewModeScope extends InheritedNotifier<CehViewModeController> {
  const CehViewModeScope({
    super.key,
    required CehViewModeController controller,
    required super.child,
  }) : super(notifier: controller);

  static CehViewModeController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CehViewModeScope>()!.notifier!;

  static CehViewModeController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CehViewModeScope>()?.notifier;
}

bool isUiAdmin(BuildContext context, CehSession session) =>
    session.user.isAdmin &&
    !(CehViewModeScope.maybeOf(context)?.viewAsOperator ?? false);
