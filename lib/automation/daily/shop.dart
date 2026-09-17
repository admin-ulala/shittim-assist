import '../model.dart';
import '../options.dart';

DailyPlan shopPlan(ShopOptions options) => DailyPlan('shop', [
  if (options.items.isNotEmpty) ...[
    DailyStep('shop.enter', 'home', 'shop.normal'),
    // One transaction: adapter checks item identities, currency and TOTAL quote
    // before confirmation. No select-all, refresh, or premium-currency fallback.
    DailyStep(
      'shop.buy',
      'shop.normal',
      'shop.purchaseVerified',
      arguments: {
        'items': options.items,
        'creditBudget': options.creditBudget,
        'currency': 'credits',
        'refresh': false,
      },
    ),
    DailyStep('navigation.home', 'shop.normal', 'home'),
  ],
]);
