import '../model.dart';
import '../options.dart';

DailyPlan craftPlan(CraftOptions options) => DailyPlan('craft', [
  if (options.claimFinished || options.quickCraftCount > 0) ...[
    DailyStep('craft.enter', 'home', 'craft'),
    if (options.claimFinished)
      DailyStep(
        'craft.claimFinished',
        'craft',
        'craft.finishedCollected',
        arguments: {'useBoosters': false, 'maxSlots': 3},
      ),
    for (var slot = 0; slot < options.quickCraftCount; slot++)
      DailyStep(
        'craft.quick',
        'craft.confirmedEmptySlot',
        'craft.started',
        arguments: {
          'ordinal': slot + 1,
          'keystones': 1,
          'keystoneBudget': options.keystoneBudget,
          'requireSavedRecipe': true,
          'useBoosters': false,
        },
      ),
    DailyStep('navigation.home', 'craft', 'home'),
  ],
]);
