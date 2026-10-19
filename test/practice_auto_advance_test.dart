import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/services/practice_auto_advance.dart';

void main() {
  testWidgets('fast practice keeps the existing 1250ms feedback interval',
      (tester) async {
    final advance = PracticeAutoAdvance();
    var calls = 0;
    advance.schedule(() => calls++);
    await tester.pump(const Duration(milliseconds: 1249));
    expect(calls, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, 1);
    advance.dispose();
  });

  testWidgets('overlapping summary and review cannot resume each other',
      (tester) async {
    final advance = PracticeAutoAdvance();
    var calls = 0;
    advance.schedule(() => calls++);
    await tester.pump(const Duration(milliseconds: 1000));
    advance.pause('summary');
    advance.pause('review');
    await tester.pump(const Duration(seconds: 10));
    advance.resume('review');
    await tester.pump(const Duration(seconds: 10));
    expect(calls, 0);
    advance.resume('summary');
    await tester.pump(const Duration(milliseconds: 1249));
    expect(calls, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, 1);
    advance.dispose();
  });

  testWidgets('reading opened before an answer finishes writing also pauses',
      (tester) async {
    final advance = PracticeAutoAdvance();
    var calls = 0;
    advance.pause('reading');
    advance.schedule(() => calls++);
    await tester.pump(const Duration(seconds: 10));
    expect(calls, 0);
    advance.resume('reading');
    await tester.pump(const Duration(milliseconds: 1250));
    expect(calls, 1);
    advance.dispose();
  });

  testWidgets(
      'navigation cancels the old advance and dispose cancels the new one',
      (tester) async {
    final advance = PracticeAutoAdvance();
    final calls = <String>[];
    advance.schedule(() => calls.add('old question'));
    advance.pause('reading');
    advance.cancel();
    advance.resume('reading');
    await tester.pump(const Duration(seconds: 10));
    expect(calls, isEmpty);
    advance.schedule(() => calls.add('new question'));
    advance.dispose();
    await tester.pump(const Duration(seconds: 10));
    expect(calls, isEmpty);
  });
}
