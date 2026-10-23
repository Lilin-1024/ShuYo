import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canvas JavaScript camera and rendering regressions', () async {
    // Execute the shipped script with a deterministic DOM/clock, without a
    // browser, native WebView, emulator, application build or npm dependencies.
    // Flutter-only environments can still run all Dart/widget tests.
    ProcessResult result;
    try {
      result = await Process.run('node', [
        'test/features/campus_map/support/canvas_regressions.mjs',
        'assets/campus_map/canvas.html',
      ]);
    } on ProcessException {
      markTestSkipped(
          'Node.js is needed for the canvas JavaScript regressions');
      return;
    }
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
}
