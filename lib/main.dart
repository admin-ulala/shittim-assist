import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/device.dart';
import 'core/engine.dart';
import 'core/overlay.dart';
import 'core/storage.dart';
import 'core/server.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ShittimApp());
}

class ShittimApp extends StatelessWidget {
  const ShittimApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '什亭助手 · Shittim Assist',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF078AC8),
        surface: const Color(0xFFF6FAFD),
      ),
      scaffoldBackgroundColor: const Color(0xFFF0F6FB),
      fontFamily: Platform.isWindows ? 'Microsoft YaHei' : null,
      fontFamilyFallback: const ['Microsoft YaHei', 'Noto Sans CJK SC'],
      cardTheme: const CardThemeData(
        elevation: 0,
        color: Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Color(0xFFF7FAFD),
      ),
    ),
    home: const Workbench(),
  );
}

class Workbench extends StatefulWidget {
  const Workbench({super.key});
  @override
  State<Workbench> createState() => _WorkbenchState();
}

class _WorkbenchState extends State<Workbench> with WidgetsBindingObserver {
  static const titles = ['总览', '设备连接', '任务计划', '运行日志', '设置'];
  static const icons = [
    Icons.dashboard_outlined,
    Icons.devices_outlined,
    Icons.checklist_rounded,
    Icons.receipt_long_outlined,
    Icons.tune_rounded,
  ];
  final adb = TextEditingController(text: 'adb');
  final address = TextEditingController(text: '127.0.0.1:16416');
  final pairAddress = TextEditingController();
  final pairCode = TextEditingController();
  final query = TextEditingController();
  int page = 0;
  bool working = false, ready = false, dryRun = true;
  int maxRuns = 1, reserve = 0, timeout = 30;
  String channel = 'bilibili', message = '正在初始化本地存储…';
  final selected = <String>{'mail', 'daily'};
  List<DeviceInfo> devices = [];
  DeviceBackend? device;
  Uint8List? screenshot;
  EventLog? log;
  ConfigStore? store;
  ServerProfile? server;
  AutomationEngine? engine;
  Map<String, dynamic> capabilities = {};
  bool get locked => working || (engine?.busy ?? false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Map<String, dynamic> overlaySnapshot() => {
    'config': config.toJson(),
    'state': engine?.state.name ?? 'idle',
    'message': engine?.error ?? stateLabel(engine?.state ?? RunState.idle),
    'locked': locked,
    'logs': (log?.entries ?? []).reversed
        .take(5)
        .map((e) => {'message': e['message'], 'level': e['level']})
        .toList(),
  };

  void syncOverlay() {
    if (!Platform.isAndroid || !ready || !mounted) return;
    unawaited(
      AndroidDevice.channel
          .invokeMethod('overlaySnapshot', overlaySnapshot())
          .catchError((Object _) {}),
    );
  }

  void engineChanged() => refresh();

  void changeConfig(VoidCallback change) {
    if (locked) return;
    setState(change);
    syncOverlay();
  }

  Future<Object?> handleOverlay(
    MethodCall call,
    OverlayCommands controls,
  ) async {
    if (!ready) throw PlatformException(code: 'NOT_READY', message: '助手正在初始化');
    if (call.method == 'overlaySnapshot') return overlaySnapshot();
    if (call.method == 'overlayPatch') {
      if (locked) throw PlatformException(code: 'BUSY', message: '请先停止任务再修改配置');
      final next = applyOverlayPatch(
        config,
        Map<String, dynamic>.from(call.arguments as Map),
      );
      working = true;
      refresh();
      try {
        await store!.save(next);
        _apply(next);
        message = '悬浮面板配置已同步并保存';
        await log!.add(message);
      } finally {
        working = false;
        refresh();
      }
      return overlaySnapshot();
    }
    await controls.handle(call);
    return null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  Future<void> showOverlay() => perform('打开悬浮控制', () async {
    if (channel != 'bilibili') throw StateError('目前仅支持国服 B 服');
    syncOverlay();
    await AndroidDevice.channel.invokeMethod('showOverlay');
    message = '悬浮球已开启：切到 B 服游戏，点击应用图标悬浮球→「开始只读诊断」。';
  });

  void refresh() {
    if (mounted) setState(() {});
    syncOverlay();
  }

  Future<void> _initialize() async {
    try {
      final directory = await applicationDirectory();
      log = EventLog(Directory('${directory.path}/logs'));
      await log!.load();
      server = await ServerProfile.load('cn');
      store = ConfigStore(File('${directory.path}/config.json'));
      engine = AutomationEngine(log!, onChanged: engineChanged);
      try {
        _apply(await store!.load());
      } catch (e) {
        await log!.add('配置读取失败，使用默认值：$e', level: 'warning');
      }
      if (Platform.isAndroid) {
        device = AndroidDevice();
        final controls = OverlayCommands(
          start: diagnose,
          pause: () => engine?.pause(),
          resume: () => engine?.resume(),
          cancel: () => engine?.cancel(),
        );
        AndroidDevice.channel.setMethodCallHandler(
          (call) => handleOverlay(call, controls),
        );
      }
      message = '准备就绪。连接设备后可运行只读诊断。';
      ready = true;
    } catch (e) {
      message = '初始化失败：$e';
    }
    refresh();
  }

  void _apply(AppConfig c) {
    adb.text = c.adbPath;
    address.text = c.address;
    channel = c.channel;
    dryRun = c.dryRun;
    maxRuns = c.maxRuns;
    reserve = c.staminaReserve;
    timeout = c.timeoutSeconds;
    selected
      ..clear()
      ..addAll(c.selected);
  }

  AppConfig get config => AppConfig(
    adbPath: adb.text.trim(),
    address: address.text.trim(),
    channel: channel,
    dryRun: dryRun,
    maxRuns: maxRuns,
    staminaReserve: reserve,
    timeoutSeconds: timeout,
    selected: selected.toList(),
  );
  Future<void> perform(String label, Future<void> Function() action) async {
    if (locked || !ready) return;
    setState(() {
      working = true;
      message = label;
    });
    try {
      await action();
    } catch (e) {
      message = redact('$label失败：$e');
      try {
        await log?.add(message, level: 'error');
      } catch (_) {}
    } finally {
      working = false;
      refresh();
    }
  }

  Future<void> scan() => perform('正在扫描设备', () async {
    devices = await AdbClient(adb.text.trim()).devices();
    final available = devices.where((d) => d.ready).toList();
    if (available.isNotEmpty && device == null) {
      device = AdbDevice(AdbClient(adb.text.trim()), available.first.id);
    }
    message = '发现 ${devices.length} 个 ADB 连接；同一模拟器的多个地址请只选一个。';
    await log!.add(message);
  });
  Future<void> capture() => perform('正在获取截图', () async {
    if (device == null) throw StateError('请先选择设备');
    screenshot = await device!.screenshot();
    message = '已获取截图，仅保留在当前界面内存中。';
    await log!.add('截图获取成功');
  });
  Future<void> diagnose() async {
    if (locked || device == null || engine == null) return;
    if (channel != 'bilibili') {
      setState(() => message = '官服包名和资源尚未验证，请选择 B 服。');
      return;
    }
    await engine!.run(
      device!,
      (c) async {
        if (Platform.isAndroid) {
          final permissions = await AndroidDevice().capabilities();
          if (permissions['accessibility'] != true ||
              permissions['capture'] != true) {
            throw StateError('请回助手开启无障碍并授权屏幕采集');
          }
        }
        await inspectDevice(c);
        screenshot = c.lastFrame;
      },
      config: config,
      expectedPackage: server!.packageFor(channel),
    );
    message = engine!.error ?? '只读诊断：${stateLabel(engine!.state)}';
    refresh();
  }

  String stateLabel(RunState s) => switch (s) {
    RunState.idle => '待机',
    RunState.running => '运行中',
    RunState.paused => '已暂停',
    RunState.stopping => '正在停止',
    RunState.succeeded => '完成',
    RunState.cancelled => '已停止',
    RunState.failed => '失败',
  };
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (Platform.isAndroid) AndroidDevice.channel.setMethodCallHandler(null);
    engine?.cancel();
    for (final c in [adb, address, pairAddress, pairCode, query]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 860;
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              Container(
                width: 228,
                color: Colors.white,
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(24, 32, 24, 30),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 34,
                            color: Color(0xFF008FCC),
                          ),
                          SizedBox(height: 14),
                          Text(
                            '什亭助手',
                            style: TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'SHITTIM ASSIST',
                            style: TextStyle(
                              fontSize: 11,
                              letterSpacing: 2,
                              color: Color(0xFF688099),
                            ),
                          ),
                        ],
                      ),
                    ),
                    for (var i = 0; i < titles.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: ListTile(
                            selected: page == i,
                            selectedTileColor: const Color(0xFFE7F5FE),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            leading: Icon(icons[i]),
                            title: Text(titles[i]),
                            onTap: () => setState(() => page = i),
                          ),
                        ),
                      ),
                    const Spacer(),
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'v0.1 · 开发预览\n国服 B 服优先',
                        style: TextStyle(color: Color(0xFF718299), height: 1.8),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(wide ? 32 : 18, 20, 18, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            titles[page],
                            style: const TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Chip(
                          avatar: Icon(
                            Icons.circle,
                            size: 10,
                            color: engine?.busy == true
                                ? Colors.orange
                                : Colors.teal,
                          ),
                          label: Text(
                            stateLabel(engine?.state ?? RunState.idle),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: '停止任务',
                          onPressed: engine?.busy == true
                              ? engine!.cancel
                              : null,
                          icon: const Icon(Icons.stop_circle_outlined),
                        ),
                      ],
                    ),
                  ),
                  if (working) const LinearProgressIndicator(minHeight: 2),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(wide ? 32 : 18),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1200),
                        child: switch (page) {
                          0 => overview(wide),
                          1 => connection(),
                          2 => tasks(),
                          3 => logs(),
                          _ => settings(),
                        },
                      ),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    color: Colors.white,
                    child: Text(
                      message,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF52708B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: page,
              onDestinationSelected: (v) => setState(() => page = v),
              destinations: [
                for (var i = 0; i < titles.length; i++)
                  NavigationDestination(icon: Icon(icons[i]), label: titles[i]),
              ],
            ),
    );
  }

  Widget card(String title, Widget child, {String? subtitle}) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                subtitle,
                style: const TextStyle(color: Color(0xFF718299), height: 1.5),
              ),
            ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    ),
  );
  double _statWidth(bool wide) {
    final available = (MediaQuery.sizeOf(context).width - (wide ? 292 : 36))
        .clamp(0.0, double.infinity);
    return available > 700
        ? (available - 48) / 4
        : ((available - 16) / 2).clamp(0.0, double.infinity);
  }

  Widget overview(bool wide) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF087EBB), Color(0xFF39BADE)],
          ),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SCHALE / ASSISTANT WORKSPACE',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 11,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '老师，工作台已就绪。',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '从连接设备开始，观察画面、验证流程。',
              style: TextStyle(color: Colors.white, height: 1.7),
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: ready && !locked && device != null
                      ? (Platform.isAndroid ? showOverlay : diagnose)
                      : null,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(Platform.isAndroid ? '开启悬浮控制' : '运行只读诊断'),
                ),
                OutlinedButton(
                  onPressed: () => setState(() => page = 1),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                  child: const Text('管理设备'),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final item in [
            ('当前设备', device?.id ?? '尚未连接'),
            ('适配区服', channel == 'bilibili' ? '国服 · B 服' : '国服 · 官服待适配'),
            ('执行模式', dryRun ? '只识别，不点击' : '允许已验证步骤'),
            ('资源预算', '青辉石 0 · 付费 0'),
          ])
            SizedBox(
              width: _statWidth(wide),
              child: card(
                item.$1,
                Text(
                  item.$2,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 20),
      card(
        '设备画面',
        screenshot == null
            ? Container(
                height: 220,
                alignment: Alignment.center,
                color: const Color(0xFFF5F9FC),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.screenshot_monitor,
                      size: 42,
                      color: Color(0xFF91AEC4),
                    ),
                    SizedBox(height: 12),
                    Text('连接后获取截图，确认当前游戏页面'),
                  ],
                ),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(screenshot!, gaplessPlayback: true),
              ),
        subtitle: '截图决定横竖屏和坐标。诊断不会领取奖励或消耗体力。',
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 10,
        children: [
          OutlinedButton.icon(
            onPressed: ready && !locked && device != null ? capture : null,
            icon: const Icon(Icons.refresh),
            label: const Text('刷新截图'),
          ),
          if (engine?.state == RunState.running)
            OutlinedButton(onPressed: engine!.pause, child: const Text('暂停')),
          if (engine?.state == RunState.paused)
            OutlinedButton(onPressed: engine!.resume, child: const Text('继续')),
        ],
      ),
    ],
  );
  Widget connection() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (Platform.isAndroid)
        card(
          '在本机运行',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '① 开启无障碍 ② 授权屏幕采集 ③ 开启悬浮控制。切到 B 服游戏，点击「什亭」展开后开始只读诊断。拖动悬浮球可移动位置；暂停、停止和关闭均在悬浮面板内。无障碍仅查询窗口根节点包名判断前台，不遍历文本。',
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton(
                    onPressed: locked
                        ? null
                        : () => perform('打开无障碍设置', () async {
                            await AndroidDevice().openAccessibility();
                            message = '请开启什亭助手无障碍服务';
                          }),
                    child: const Text('开启无障碍'),
                  ),
                  FilledButton.tonal(
                    onPressed: locked
                        ? null
                        : () => perform('请求屏幕采集', () async {
                            await AndroidDevice().requestCapture();
                            message = '屏幕采集已授权';
                          }),
                    child: const Text('授权屏幕采集'),
                  ),
                  FilledButton.tonal(
                    onPressed: locked ? null : showOverlay,
                    child: const Text('开启悬浮控制'),
                  ),
                  OutlinedButton(
                    onPressed: locked
                        ? null
                        : () => perform('检查权限', () async {
                            capabilities = await AndroidDevice().capabilities();
                            message = '权限状态已更新';
                          }),
                    child: const Text('检查权限'),
                  ),
                  OutlinedButton(
                    onPressed: locked
                        ? null
                        : () => perform('停止采集', () async {
                            await AndroidDevice().stopCapture();
                            message = '屏幕采集已停止';
                          }),
                    child: const Text('停止采集'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '无障碍：${capabilities['accessibility'] == true ? '已开启' : '未确认'}  ·  采集：${capabilities['capture'] == true ? '已开启' : '未确认'}',
              ),
            ],
          ),
        )
      else ...[
        card(
          'ADB 连接',
          Column(
            children: [
              TextField(
                controller: adb,
                enabled: !locked,
                decoration: const InputDecoration(
                  labelText: 'ADB 可执行文件',
                  helperText: '可使用系统 PATH 中的 adb，或模拟器附带的 adb.exe 完整路径',
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: address,
                enabled: !locked,
                decoration: const InputDecoration(
                  labelText: '网络地址',
                  hintText: '127.0.0.1:16416',
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: ready && !locked ? scan : null,
                    icon: const Icon(Icons.search),
                    label: const Text('扫描 USB / 模拟器'),
                  ),
                  OutlinedButton(
                    onPressed: ready && !locked
                        ? () => perform('连接设备', () async {
                            message = await AdbClient(
                              adb.text.trim(),
                            ).connect(address.text.trim());
                            devices = await AdbClient(
                              adb.text.trim(),
                            ).devices();
                            if (devices.any(
                              (d) => d.id == address.text.trim() && d.ready,
                            )) {
                              device = AdbDevice(
                                AdbClient(adb.text.trim()),
                                address.text.trim(),
                              );
                              screenshot = null;
                            }
                            await log!.add(message);
                          })
                        : null,
                    child: const Text('连接地址'),
                  ),
                ],
              ),
              for (final d in devices)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    d.ready ? Icons.phone_android : Icons.warning_amber,
                  ),
                  title: Text(d.name),
                  subtitle: Text('${d.id} · ${d.ready ? '可用' : '离线或未授权'}'),
                  trailing: device?.id == d.id
                      ? const Icon(Icons.check_circle, color: Colors.teal)
                      : null,
                  onTap: locked || !d.ready
                      ? null
                      : () => setState(() {
                          device = AdbDevice(AdbClient(adb.text.trim()), d.id);
                          screenshot = null;
                        }),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        card(
          '无线调试配对',
          Column(
            children: [
              TextField(
                controller: pairAddress,
                enabled: !locked,
                decoration: const InputDecoration(labelText: '配对地址（通常不同于连接端口）'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: pairCode,
                enabled: !locked,
                obscureText: true,
                decoration: const InputDecoration(labelText: '六位配对码'),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: ready && !locked
                    ? () => perform('正在配对', () async {
                        message = await AdbClient(
                          adb.text.trim(),
                        ).pair(pairAddress.text.trim(), pairCode.text.trim());
                        pairCode.clear();
                        await log!.add('配对命令完成，请使用连接端口连接');
                      })
                    : null,
                child: const Text('配对'),
              ),
            ],
          ),
          subtitle: 'Android 无线调试；旧版模拟器 ADB 可能不支持 pair。',
        ),
      ],
    ],
  );
  Widget tasks() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      card(
        '国服日常计划',
        Column(
          children: [
            const Text('当前提供计划配置。任务资源仍在适配，尚不能执行领奖或扫荡；可先在总览运行设备诊断。'),
            const SizedBox(height: 12),
            for (final item in [
              ('signin', '签到', '登录与签到弹窗'),
              ('mail', '邮件奖励', '领取可领取邮件'),
              ('daily', '日常奖励', '每日 / 每周任务奖励'),
              ('sweep', '关卡扫荡', '已三星关卡与体力预算'),
            ])
              CheckboxListTile(
                value: selected.contains(item.$1),
                contentPadding: EdgeInsets.zero,
                onChanged: locked
                    ? null
                    : (v) => changeConfig(() {
                        v == true
                            ? selected.add(item.$1)
                            : selected.remove(item.$1);
                      }),
                title: Text(item.$2),
                subtitle: Text('${item.$3} · 待实机适配'),
              ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      card(
        '运行约束',
        Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('只识别，不点击'),
              subtitle: const Text('默认开启。关闭也不会启用尚未适配的任务。'),
              value: dryRun,
              onChanged: locked ? null : (v) => changeConfig(() => dryRun = v),
            ),
            number('计划次数', maxRuns, 1, 999, (v) => maxRuns = v),
            number('保留体力', reserve, 0, 999, (v) => reserve = v),
            number('任务超时（秒）', timeout, 5, 300, (v) => timeout = v),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.shield_outlined),
              title: Text('青辉石消费与付费操作关闭'),
              subtitle: Text('开发预览版本不提供消费入口'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      saveButton(),
    ],
  );
  Widget number(
    String label,
    int value,
    int min,
    int max,
    void Function(int) change,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: locked || value <= min
              ? null
              : () => changeConfig(() => change(value - 1)),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(width: 38, child: Text('$value', textAlign: TextAlign.center)),
        IconButton(
          onPressed: locked || value >= max
              ? null
              : () => changeConfig(() => change(value + 1)),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    ),
  );
  Widget saveButton() => Align(
    alignment: Alignment.centerLeft,
    child: FilledButton.icon(
      onPressed: ready && !locked
          ? () => perform('保存配置', () async {
              await store!.save(config);
              message = '配置已保存';
              await log!.add(message);
            })
          : null,
      icon: const Icon(Icons.save_outlined),
      label: const Text('保存配置'),
    ),
  );
  Widget logs() => card(
    '运行事件',
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: query,
          onChanged: (_) => refresh(),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: '搜索消息、错误或步骤',
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: ready && !locked
                ? () => perform('导出日志', () async {
                    final path = await log!.export();
                    message = '日志已导出：$path';
                  })
                : null,
            icon: const Icon(Icons.download_outlined),
            label: const Text('导出脱敏日志'),
          ),
        ),
        if (log?.entries.isEmpty ?? true)
          const Padding(padding: EdgeInsets.all(30), child: Text('尚无运行记录。')),
        for (final e in (log?.entries ?? []).reversed.where(
          (e) => jsonEncode(e).toLowerCase().contains(query.text.toLowerCase()),
        ))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              e['level'] == 'error' ? Icons.error_outline : Icons.info_outline,
              color: e['level'] == 'error'
                  ? Colors.redAccent
                  : const Color(0xFF1697C4),
            ),
            title: SelectableText(e['message'] as String),
            subtitle: Text('${e['time']} · ${e['step'] ?? e['level']}'),
          ),
      ],
    ),
  );
  Widget settings() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      card(
        '客户端',
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: channel,
              decoration: const InputDecoration(labelText: '区服与渠道'),
              items: const [
                DropdownMenuItem(
                  value: 'bilibili',
                  child: Text('国服 · B 服（优先适配）'),
                ),
                DropdownMenuItem(
                  value: 'official',
                  child: Text('国服 · 官服（待适配）'),
                ),
              ],
              onChanged: locked
                  ? null
                  : (v) => changeConfig(() => channel = v!),
            ),
            const SizedBox(height: 16),
            const Text('日服、港澳台／国际服将在后续资源包中加入。'),
          ],
        ),
      ),
      const SizedBox(height: 18),
      card(
        '配置与隐私',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('配置与日志保存在系统应用数据目录。截图默认不落盘，不上传账号或设备数据。'),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton(
                  onPressed: ready && !locked
                      ? () => _configDialog(false)
                      : null,
                  child: const Text('导出配置 JSON'),
                ),
                OutlinedButton(
                  onPressed: ready && !locked
                      ? () => _configDialog(true)
                      : null,
                  child: const Text('导入配置 JSON'),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      saveButton(),
      const SizedBox(height: 24),
      const Text(
        'Shittim Assist · MIT 开源\n非官方工具，与游戏发行方无隶属关系。',
        style: TextStyle(color: Color(0xFF718299), height: 1.8),
      ),
    ],
  );
  Future<void> _configDialog(bool importing) async {
    final controller = TextEditingController(
      text: importing
          ? ''
          : const JsonEncoder.withIndent('  ').convert(config.toJson()),
    );
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(importing ? '导入配置' : '导出配置'),
        content: SizedBox(
          width: 560,
          child: TextField(
            controller: controller,
            readOnly: !importing,
            maxLines: 14,
            decoration: const InputDecoration(hintText: '粘贴配置 JSON'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          if (importing)
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('校验并导入'),
            ),
        ],
      ),
    );
    // Dialog route animations can retain the controller briefly.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    controller.dispose();
    if (result != null && mounted) {
      await perform('导入配置', () async {
        final imported = AppConfig.fromJson(
          jsonDecode(result) as Map<String, dynamic>,
        );
        await store!.save(imported);
        _apply(imported);
        message = '配置已校验并导入';
      });
    }
  }
}
