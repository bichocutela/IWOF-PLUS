import 'package:flutter_test/flutter_test.dart';
import 'package:iwof_plus/services/plus_api.dart';

void main() {
  final sentAt = DateTime.utc(2026, 10, 28, 12);
  test('history confirmation requires the exact course ID', () {
    final attempts = [
      PlusAttempt('course-other', 'Mesmo nome', true, 100,
          sentAt.add(const Duration(seconds: 2))),
      PlusAttempt('course-1', 'Mesmo nome', false, 60,
          sentAt.add(const Duration(seconds: 3))),
    ];
    final match = PlusAttempt.confirmedForCourse(
      attempts, 'course-1', sentAt,
    );
    expect(match?.approved, false);
    expect(match?.courseId, 'course-1');
  });

  test('old attempts do not confirm a new official submission', () {
    final attempts = [
      PlusAttempt('course-1', 'Curso', true, 100,
          sentAt.subtract(const Duration(days: 2))),
    ];
    expect(PlusAttempt.confirmedForCourse(attempts, 'course-1', sentAt),
        isNull);
  });

  test('missing timestamps cannot confirm a new submission', () {
    final attempts = [
      const PlusAttempt('course-1', 'Curso', true, 100, null),
    ];
    expect(PlusAttempt.confirmedForCourse(attempts, 'course-1', sentAt),
        isNull);
  });

  test('course attempt reads the real course identifier', () {
    final attempt = PlusAttempt.fromJson({
      'approved': true,
      'percentage_correction': 85,
      'updated_at': '2026-10-28T12:00:00Z',
      'course': {'id': 'c-1', 'name': 'Treinamento'},
    });
    expect(attempt.courseId, 'c-1');
    expect(attempt.percentage, 85);
  });
}
