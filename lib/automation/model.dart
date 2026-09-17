/// Device-independent daily workflow contracts. No screen coordinates belong here.
enum ContentCategory { daily, stages, pvp, periodicBattle, eventMinigame }

enum ModuleStatus { logicDraft, placeholder }

enum StepResult { completed, alreadyDone, exhausted, unavailable, unknown }

class ModuleInfo {
  const ModuleInfo(this.id, this.name, this.category, this.status);
  final String id, name;
  final ContentCategory category;
  final ModuleStatus status;
}

/// An operation includes its semantic verification contract. The page adapter
/// must recognize both sides and must never infer success from a missing image.
class DailyStep {
  DailyStep(
    this.id,
    this.before,
    this.after, {
    Map<String, Object> arguments = const {},
  }) : arguments = Map.unmodifiable(arguments);
  final String id, before, after;
  final Map<String, Object> arguments;
}

class DailyPlan {
  DailyPlan(this.moduleId, Iterable<DailyStep> steps)
    : steps = List.unmodifiable(steps);
  final String moduleId;
  final List<DailyStep> steps;
}

/// Implement per server/layout, using RunContext for ALL input and cancellation.
/// Every call is bounded by the supplied RunContext deadline. An ambiguous
/// postcondition returns unknown; it must never replay a purchase or claim.
abstract interface class DailyPageAdapter {
  Set<String> get supportedOperations;
  Future<StepResult> execute(DailyStep step);
  Future<void> saveFailureEvidence(String moduleId, String stepId);
}

class DailyReport {
  DailyReport(this.moduleId, this.result, this.completedSteps);
  final String moduleId;
  final StepResult result;
  final int completedSteps;
}
