import '../model.dart';
import '../options.dart';

DailyPlan schedulePlan(ScheduleOptions options) => DailyPlan('schedule', [
  if (options.targets.isNotEmpty) ...[
    DailyStep('schedule.enter', 'home', 'schedule'),
    for (final target in options.targets)
      DailyStep(
        'schedule.execute',
        'schedule',
        'schedule.reportConfirmed',
        arguments: {
          'area': target.area,
          'room': target.room,
          'ticketLimit': options.ticketLimit,
          'buyTickets': false,
          'maxScrolls': 3,
        },
      ),
    DailyStep('navigation.home', 'schedule', 'home'),
  ],
]);
