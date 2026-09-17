/// Module options are independent of device/connection configuration.
/// Defaults never schedule a resource-consuming operation.
class CafeOptions {
  const CafeOptions({
    this.claimEarnings = true,
    this.touchStudents = false,
    this.visitBranch = false,
    this.inviteStudent,
  });
  final bool claimEarnings, touchStudents, visitBranch;
  final String? inviteStudent;
}

class ScheduleTarget {
  const ScheduleTarget(this.area, this.room);
  final String area, room;
}

class ScheduleOptions {
  ScheduleOptions({
    Iterable<ScheduleTarget> targets = const [],
    this.ticketLimit = 0,
  }) : targets = List.unmodifiable(targets) {
    if (ticketLimit < 0 ||
        ticketLimit > 99 ||
        this.targets.length > ticketLimit ||
        this.targets.any(
          (t) => t.area.trim().isEmpty || t.room.trim().isEmpty,
        ) ||
        this.targets.map((t) => (t.area, t.room)).toSet().length !=
            this.targets.length) {
      throw ArgumentError('日程地点须唯一、非空，且数量不能超过日程券上限（0–99）');
    }
  }
  final List<ScheduleTarget> targets;
  final int ticketLimit;
}

class CraftOptions {
  CraftOptions({
    this.claimFinished = true,
    this.quickCraftCount = 0,
    this.keystoneBudget = 0,
  }) {
    if (quickCraftCount < 0 ||
        quickCraftCount > 3 ||
        keystoneBudget < quickCraftCount ||
        keystoneBudget > 3) {
      throw ArgumentError('快速制造最多三次，每次一颗制造石，须设置预算');
    }
  }
  final bool claimFinished;
  final int quickCraftCount, keystoneBudget;
}

class ShopOptions {
  ShopOptions({Iterable<String> items = const [], this.creditBudget = 0})
    : items = List.unmodifiable(items) {
    if (creditBudget < 0 ||
        this.items.length > 30 ||
        this.items.any((id) => id.trim().isEmpty) ||
        this.items.toSet().length != this.items.length ||
        (this.items.isNotEmpty && creditBudget == 0)) {
      throw ArgumentError('商品须唯一、非空；购买须设置信用点总预算');
    }
  }
  final List<String> items;
  final int creditBudget;
}
