import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shittim_assist/automation/catalog.dart';
import 'package:shittim_assist/automation/daily/cafe.dart';
import 'package:shittim_assist/automation/daily/craft.dart';
import 'package:shittim_assist/automation/daily/schedule.dart';
import 'package:shittim_assist/automation/daily/shop.dart';
import 'package:shittim_assist/automation/daily/social.dart';
import 'package:shittim_assist/automation/model.dart';
import 'package:shittim_assist/automation/options.dart';
import 'package:shittim_assist/automation/runner.dart';
import 'package:shittim_assist/core/device.dart';
import 'package:shittim_assist/core/engine.dart';
import 'package:shittim_assist/core/storage.dart';

class NoDevice implements DeviceBackend {
  @override
  String get id => 'offline';
  @override
  Future<String> foregroundPackage() async =>
      throw StateError('No device access');
  @override
  Future<Uint8List> screenshot() async => throw StateError('No device access');
  @override
  Future<void> tap(int x, int y) async => throw StateError('No device access');
  @override
  Future<void> back() async => throw StateError('No device access');
  @override
  Future<void> swipe(int x1, int y1, int x2, int y2, Duration duration) async =>
      throw StateError('No device access');
}

class ScriptedPages implements DailyPageAdapter {
  ScriptedPages(this.supportedOperations);
  @override
  final Set<String> supportedOperations;
  final calls = <String>[];
  StepResult result = StepResult.completed;
  int evidence = 0;
  void Function()? onExecute;
  @override
  Future<StepResult> execute(DailyStep step) async {
    calls.add(step.id);
    onExecute?.call();
    return result;
  }

  @override
  Future<void> saveFailureEvidence(String moduleId, String stepId) async {
    evidence++;
  }
}

void main() {
  late Directory temp;
  late RunContext context;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('shittim-daily-');
    context = RunContext(
      NoDevice(),
      RunControl(const Duration(seconds: 5)),
      EventLog(temp),
      'offline',
      dryRun: false,
      expectedPackage: 'game',
    );
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('catalog contains ten daily modules with explicit placeholders', () {
    expect(
      automationCatalog.where((m) => m.category == ContentCategory.daily),
      hasLength(10),
    );
    expect(moduleInfo('mail').status, ModuleStatus.placeholder);
    expect(() => moduleInfo('typo'), throwsArgumentError);
  });
  test('defaults schedule no ticket, stone, or credit consumption', () {
    expect(schedulePlan(ScheduleOptions()).steps, isEmpty);
    expect(shopPlan(ShopOptions()).steps, isEmpty);
    expect(
      craftPlan(CraftOptions()).steps.any((s) => s.id == 'craft.quick'),
      isFalse,
    );
    expect(
      cafePlan(const CafeOptions()).steps.any((s) => s.id == 'cafe.invite'),
      isFalse,
    );
  });
  test(
    'schedule rejects repeated locations and insufficient ticket budget',
    () {
      expect(
        () => ScheduleOptions(targets: [const ScheduleTarget('A', 'B')]),
        throwsArgumentError,
      );
      expect(
        () => ScheduleOptions(
          ticketLimit: 2,
          targets: [
            const ScheduleTarget('A', 'B'),
            const ScheduleTarget('A', 'B'),
          ],
        ),
        throwsArgumentError,
      );
    },
  );
  test(
    'resource options reject unsafe budgets and retain immutable item list',
    () {
      expect(() => CraftOptions(quickCraftCount: 1), throwsArgumentError);
      expect(
        () => CraftOptions(quickCraftCount: 4, keystoneBudget: 4),
        throwsArgumentError,
      );
      expect(() => ShopOptions(items: ['item']), throwsArgumentError);
      final items = ['item'];
      final options = ShopOptions(items: items, creditBudget: 100);
      items.clear();
      expect(options.items, ['item']);
      expect(shopPlan(options).steps[1].arguments['creditBudget'], 100);
    },
  );
  test(
    'whole queue preflight rejects missing adapter before first action',
    () async {
      final pages = ScriptedPages({'social.enter'});
      await expectLater(
        DailyRunner(context, pages).run([socialPlan()]),
        throwsUnsupportedError,
      );
      expect(pages.calls, isEmpty);
    },
  );
  test('placeholder cannot pass as an empty successful task', () async {
    final pages = ScriptedPages({});
    await expectLater(
      DailyRunner(context, pages).run([DailyPlan('mail', [])]),
      throwsUnsupportedError,
    );
    expect(pages.calls, isEmpty);
  });
  test('unknown outcome saves evidence and never retries input', () async {
    final plan = socialPlan();
    final pages = ScriptedPages(plan.steps.map((s) => s.id).toSet())
      ..result = StepResult.unknown;
    await expectLater(
      DailyRunner(context, pages).run([plan]),
      throwsStateError,
    );
    expect(pages.calls, ['social.enter']);
    expect(pages.evidence, 1);
  });
  test(
    'resource exhaustion stops queue without blind return navigation',
    () async {
      final plan = socialPlan();
      final pages = ScriptedPages(plan.steps.map((s) => s.id).toSet())
        ..result = StepResult.exhausted;
      final reports = await DailyRunner(context, pages).run([plan]);
      expect(reports.single.result, StepResult.exhausted);
      expect(reports.single.completedSteps, 0);
      expect(pages.calls, ['social.enter']);
    },
  );
  test(
    'cancel between steps stops without extra actions or screenshots',
    () async {
      final plan = socialPlan();
      final pages = ScriptedPages(plan.steps.map((s) => s.id).toSet())
        ..onExecute = () {
          context.control.cancelled = true;
        };
      await expectLater(
        DailyRunner(context, pages).run([plan]),
        throwsA(isA<RunCancelled>()),
      );
      expect(pages.calls, hasLength(1));
      expect(pages.evidence, 0);
    },
  );
  test('readonly mode cannot claim a simulated successful workflow', () async {
    final readonly = RunContext(
      NoDevice(),
      context.control,
      context.log,
      'preview',
      dryRun: true,
      expectedPackage: 'game',
    );
    final plan = socialPlan();
    final pages = ScriptedPages(plan.steps.map((s) => s.id).toSet());
    await expectLater(
      DailyRunner(readonly, pages).run([plan]),
      throwsStateError,
    );
    expect(pages.calls, isEmpty);
  });
  test('verified successful steps retain order and count', () async {
    final plan = socialPlan();
    final pages = ScriptedPages(plan.steps.map((s) => s.id).toSet());
    final reports = await DailyRunner(context, pages).run([plan]);
    expect(pages.calls, plan.steps.map((s) => s.id).toList());
    expect(reports.single.completedSteps, 4);
  });
}
