import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('splash session bootstrap cannot wait forever', () {
    final source = File('lib/screens/splash_screen.dart').readAsStringSync();

    expect(source, contains(".timeout(const Duration(seconds: 12))"));
    expect(source, contains('catch (error, stackTrace)'));
    expect(source, contains('debugPrintStack(stackTrace: stackTrace)'));
    expect(source, contains('Navigator.of(context).pushReplacement'));
  });
}
