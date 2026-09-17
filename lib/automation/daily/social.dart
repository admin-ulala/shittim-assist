import '../model.dart';

DailyPlan socialPlan({bool signIn = true}) => DailyPlan('social', [
  if (signIn) ...[
    DailyStep('social.enter', 'home', 'social'),
    DailyStep('social.club', 'social', 'social.club'),
    DailyStep('social.signIn', 'social.club', 'social.attendanceConfirmed'),
    DailyStep('navigation.home', 'social.club', 'home'),
  ],
]);
