import '../model.dart';
import '../options.dart';

DailyPlan cafePlan(CafeOptions options) {
  if (options.inviteStudent != null && options.inviteStudent!.trim().isEmpty) {
    throw ArgumentError('邀请学生名称不能为空');
  }
  final steps = <DailyStep>[
    DailyStep('cafe.enter', 'home', 'cafe.main'),
    DailyStep('cafe.dismissVisitors', 'cafe.main', 'cafe.main'),
    if (options.claimEarnings)
      DailyStep('cafe.claim', 'cafe.main', 'cafe.earningsClaimedOrEmpty'),
    if (options.inviteStudent != null)
      DailyStep(
        'cafe.invite',
        'cafe.main',
        'cafe.invited',
        arguments: {'student': options.inviteStudent!, 'invitationLimit': 1},
      ),
    if (options.touchStudents)
      DailyStep(
        'cafe.touch',
        'cafe.main',
        'cafe.main',
        arguments: {'maxStudents': 6, 'maxViews': 6},
      ),
    if (options.visitBranch) ...[
      DailyStep('cafe.branch', 'cafe.main', 'cafe.branch'),
      DailyStep('cafe.dismissVisitors', 'cafe.branch', 'cafe.branch'),
      if (options.touchStudents)
        DailyStep(
          'cafe.touch',
          'cafe.branch',
          'cafe.branch',
          arguments: {'maxStudents': 6, 'maxViews': 6},
        ),
    ],
    DailyStep('navigation.home', 'cafe', 'home'),
  ];
  return DailyPlan('cafe', steps);
}
