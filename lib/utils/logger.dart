import 'package:flutter/foundation.dart';

/// Lightweight logging utility to centrally control verbose logs in debug.
class Log {
  /// Toggle to enable/disable verbose logs during debug runs.
  static const bool verbose = false;

  /// Verbose log: only prints when in debug mode and [verbose] is true.
  static void v(Object? message) {
    if (kDebugMode && verbose) {
      debugPrint(message?.toString());
    }
  }
}
