import 'package:flutter/foundation.dart';

/// Global tab index notifier for MainShell.
/// Set value to switch tabs without navigation stack manipulation.
final appTabNotifier = ValueNotifier<int>(0);
