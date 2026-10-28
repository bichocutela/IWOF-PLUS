import 'package:flutter_test/flutter_test.dart';
import 'package:iwof_plus/services/app_updates.dart';

void main() {
  test('semantic versions are compared numerically', () {
    expect(AppUpdates.compareVersions('v0.2.0', '0.1.0'), greaterThan(0));
    expect(AppUpdates.compareVersions('v0.10.0', '0.9.9'), greaterThan(0));
    expect(AppUpdates.compareVersions('v1.0.0', '1.0.0'), 0);
    expect(AppUpdates.compareVersions('v0.1.0', '0.2.0'), lessThan(0));
  });

  test('unrecognizable version is rejected', () {
    expect(() => AppUpdates.compareVersions('invalid', '0.2.0'),
        throwsFormatException);
  });
}
