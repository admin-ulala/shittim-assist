import 'model.dart';

const automationCatalog = [
  ModuleInfo('cafe', '咖啡厅', ContentCategory.daily, ModuleStatus.logicDraft),
  ModuleInfo('schedule', '日程', ContentCategory.daily, ModuleStatus.logicDraft),
  ModuleInfo('social', '社交', ContentCategory.daily, ModuleStatus.logicDraft),
  ModuleInfo('craft', '制造', ContentCategory.daily, ModuleStatus.logicDraft),
  ModuleInfo('shop', '商店', ContentCategory.daily, ModuleStatus.logicDraft),
  ModuleInfo(
    'business',
    '业务区',
    ContentCategory.daily,
    ModuleStatus.placeholder,
  ),
  ModuleInfo(
    'workTasks',
    '工作任务',
    ContentCategory.daily,
    ModuleStatus.placeholder,
  ),
  ModuleInfo('momotalk', '桃信', ContentCategory.daily, ModuleStatus.placeholder),
  ModuleInfo('mail', '邮件', ContentCategory.daily, ModuleStatus.placeholder),
  ModuleInfo(
    'dailyRewards',
    '每日奖励',
    ContentCategory.daily,
    ModuleStatus.placeholder,
  ),
  ModuleInfo(
    'stages',
    '推图与重复刷本',
    ContentCategory.stages,
    ModuleStatus.placeholder,
  ),
  ModuleInfo('pvp', '战术对抗赛', ContentCategory.pvp, ModuleStatus.placeholder),
  ModuleInfo(
    'periodicBattle',
    '周期性战役',
    ContentCategory.periodicBattle,
    ModuleStatus.placeholder,
  ),
  ModuleInfo(
    'eventMinigame',
    '活动小游戏',
    ContentCategory.eventMinigame,
    ModuleStatus.placeholder,
  ),
];

ModuleInfo moduleInfo(String id) => automationCatalog.firstWhere(
  (module) => module.id == id,
  orElse: () => throw ArgumentError('未知模块：$id'),
);
