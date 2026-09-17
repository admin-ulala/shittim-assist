import '../core/engine.dart';
import 'catalog.dart';
import 'model.dart';

/// Call within AutomationEngine.run so device locking, deadline and stop apply.
/// This runner is not connected to the UI until a real page adapter is supplied.
class DailyRunner {
  DailyRunner(this.context, this.adapter);
  final RunContext context;
  final DailyPageAdapter adapter;

  Future<List<DailyReport>> run(List<DailyPlan> plans) async {
    // Preflight the entire queue BEFORE performing any device operation.
    if (plans.map((p) => p.moduleId).toSet().length != plans.length) {
      throw ArgumentError('同一计划不能重复包含模块');
    }
    for (final plan in plans) {
      if (moduleInfo(plan.moduleId).status == ModuleStatus.placeholder) {
        throw UnsupportedError('模块尚未实现：${plan.moduleId}');
      }
      for (final step in plan.steps) {
        if (!adapter.supportedOperations.contains(step.id)) {
          throw UnsupportedError('页面操作尚未适配：${step.id}');
        }
      }
    }
    if (context.dryRun) {
      // A preview cannot observe postconditions of inputs it never sent.
      throw StateError('请查看流程计划；只读模式不模拟任务完成');
    }
    final reports = <DailyReport>[];
    for (final plan in plans) {
      var completed = 0;
      var result = StepResult.alreadyDone;
      for (final step in plan.steps) {
        await context.control.checkpoint();
        await context.log.add(
          '${plan.moduleId}: ${step.id}',
          runId: context.runId,
          step: step.id,
        );
        try {
          result = await adapter.execute(step);
          await context.control.checkpoint();
          if (result == StepResult.unknown) {
            throw StateError('无法确认步骤结果：${step.id}，请人工检查');
          }
          await context.log.add(
            '步骤结果：${result.name}',
            runId: context.runId,
            step: step.id,
          );
        } on RunCancelled {
          rethrow;
        } catch (_) {
          try {
            await adapter.saveFailureEvidence(plan.moduleId, step.id);
          } catch (_) {}
          rethrow;
        }
        if (result == StepResult.exhausted ||
            result == StepResult.unavailable) {
          // Do not navigate blindly from a resource/purchase dialog. Leave the
          // queue stopped; user inspects and starts a fresh plan explicitly.
          reports.add(DailyReport(plan.moduleId, result, completed));
          return reports;
        }
        completed++;
      }
      reports.add(DailyReport(plan.moduleId, result, completed));
    }
    return reports;
  }
}
