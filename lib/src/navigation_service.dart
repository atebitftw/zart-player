import 'package:flutter/material.dart';

/// Global navigation service providing access to BuildContext from anywhere.
/// Used by ZartIOProvider to show save/restore dialogs.
class NavigationService {
  static GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
}
