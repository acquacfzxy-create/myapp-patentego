import 'package:flutter_test/flutter_test.dart';
import 'package:lingua_patente/services/practice_auto_advance.dart';

void main() {
  test('switch timing is set on its own: 600ms correct, 1000ms wrong', () {
    expect(PracticeAutoAdvance.correctDelay, const Duration(milliseconds: 600));
    expect(PracticeAutoAdvance.wrongDelay, const Duration(milliseconds: 1000));
    // 答對動效約 420ms，在答對切題前播完。
    expect(PracticeAutoAdvance.correctDelay,
        greaterThan(const Duration(milliseconds: 420)));
  });

  testWidgets('fast practice advances after the scheduled interval',
      (tester) async {
    final advance = PracticeAutoAdvance();
    var calls = 0;
    advance.schedule(() => calls++,
        delay: PracticeAutoAdvance.correctDelay);
    await tester.pump(const Duration(milliseconds: 599));
    expect(calls, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, 1);
    advance.schedule(() => calls++);
    await tester.pump(const Duration(milliseconds: 999));
    expect(calls, 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, 2);
    advance.dispose();
  });

  testWidgets('saving runs alongside the interval without restarting it',
      (tester) async {
    final advance = PracticeAutoAdvance();
    var calls = 0;
    // 存檔比停留快：到點即切題。
    advance.schedule(() => calls++,
        delay: PracticeAutoAdvance.correctDelay);
    advance.hold('saving:a');
    await tester.pump(const Duration(milliseconds: 200));
    advance.release('saving:a');
    await tester.pump(const Duration(milliseconds: 399));
    expect(calls, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, 1);

    // 存檔比停留慢：存完立即切題，不再重新計時。
    advance.schedule(() => calls++,
        delay: PracticeAutoAdvance.correctDelay);
    advance.hold('saving:b');
    await tester.pump(const Duration(milliseconds: 900));
    expect(calls, 1);
    advance.release('saving:b');
    expect(calls, 2);
    advance.dispose();
  });

  testWidgets('a stale save from the previous question cannot release a new one',
      (tester) async {
    final advance = PracticeAutoAdvance();
    final calls = <String>[];
    advance.schedule(() => calls.add('a'));
    advance.hold('saving:a');
    advance.cancel();
    advance.schedule(() => calls.add('b'));
    advance.hold('saving:b');
    advance.release('saving:a');
    await tester.pump(const Duration(seconds: 5));
    expect(calls, isEmpty);
    advance.release('saving:b');
    expect(calls, ['b']);
    advance.dispose();
  });

  testWidgets('pausing while saving waits for both, then a fresh interval',
      (tester) async {
    final advance = PracticeAutoAdvance();
    var calls = 0;
    advance.schedule(() => calls++,
        delay: PracticeAutoAdvance.correctDelay);
    advance.hold('saving:a');
    await tester.pump(const Duration(milliseconds: 700));
    advance.pause('reading');
    advance.release('saving:a');
    await tester.pump(const Duration(seconds: 10));
    expect(calls, 0);
    advance.resume('reading');
    await tester.pump(const Duration(milliseconds: 599));
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
    await tester.pump(const Duration(milliseconds: 500));
    advance.pause('summary');
    advance.pause('review');
    await tester.pump(const Duration(seconds: 10));
    advance.resume('review');
    await tester.pump(const Duration(seconds: 10));
    expect(calls, 0);
    advance.resume('summary');
    await tester.pump(const Duration(milliseconds: 999));
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
    await tester.pump(const Duration(milliseconds: 1000));
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
