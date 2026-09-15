import 'dart:convert';
import 'dart:io';

class AppConfig {
  AppConfig({
    this.adbPath = 'adb',
    this.address = '127.0.0.1:16416',
    this.channel = 'bilibili',
    this.dryRun = true,
    this.maxRuns = 1,
    this.staminaReserve = 0,
    this.timeoutSeconds = 30,
    this.selected = const ['mail', 'daily'],
  });
  final String adbPath, address, channel;
  final bool dryRun;
  final int maxRuns, staminaReserve, timeoutSeconds;
  final List<String> selected;
  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'adbPath': adbPath,
    'address': address,
    'channel': channel,
    'dryRun': dryRun,
    'maxRuns': maxRuns,
    'staminaReserve': staminaReserve,
    'timeoutSeconds': timeoutSeconds,
    'selected': selected,
    'premiumCurrencyBudget': 0,
  };
  factory AppConfig.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1) throw const FormatException('不支持的配置版本');
    if (json['premiumCurrencyBudget'] != 0) {
      throw const FormatException('本版本不支持青辉石消费');
    }
    final c = AppConfig(
      adbPath: json['adbPath'] as String,
      address: json['address'] as String,
      channel: json['channel'] as String,
      dryRun: json['dryRun'] as bool,
      maxRuns: json['maxRuns'] as int,
      staminaReserve: json['staminaReserve'] as int,
      timeoutSeconds: json['timeoutSeconds'] as int,
      selected: List<String>.from(json['selected'] as List),
    );
    if (c.adbPath.trim().isEmpty ||
        !['bilibili', 'official'].contains(c.channel) ||
        c.maxRuns < 1 ||
        c.maxRuns > 999 ||
        c.staminaReserve < 0 ||
        c.timeoutSeconds < 5 ||
        c.timeoutSeconds > 300 ||
        c.selected.any(
          (id) => !['mail', 'daily', 'sweep', 'signin'].contains(id),
        )) {
      throw const FormatException('配置值超出支持范围');
    }
    return c;
  }
}

String redact(String value) => value
    .replaceAll(RegExp(r'github_pat_[A-Za-z0-9_]+'), '[REDACTED]')
    .replaceAll(RegExp(r'gh[pousr]_[A-Za-z0-9_]+'), '[REDACTED]')
    .replaceAll(RegExp(r'(?i:bearer)\s+\S+'), 'Bearer [REDACTED]');

class EventLog {
  EventLog(this.directory);
  final Directory directory;
  final List<Map<String, dynamic>> entries = [];
  Future<void> load() async {
    final file = File('${directory.path}/events.jsonl');
    if (!await file.exists()) return;
    final lines = await file.readAsLines();
    entries.clear();
    for (final line in lines.skip(
      lines.length > 500 ? lines.length - 500 : 0,
    )) {
      try {
        final event = jsonDecode(line) as Map<String, dynamic>;
        event['message'] = redact(event['message'] as String);
        entries.add(event);
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
  }

  Future<void> _tail = Future.value();
  Future<void> add(
    String message, {
    String level = 'info',
    String? runId,
    String? step,
  }) {
    final event = <String, dynamic>{
      'time': DateTime.now().toUtc().toIso8601String(),
      'level': level,
      'message': redact(message),
      'runId': runId,
      'step': step,
    };
    entries.add(event);
    if (entries.length > 500) entries.removeAt(0);
    final operation = _tail.then((_) async {
      await directory.create(recursive: true);
      final file = File('${directory.path}/events.jsonl');
      if (await file.exists() && await file.length() > 2 * 1024 * 1024) {
        final old = File('${directory.path}/events.previous.jsonl');
        if (await old.exists()) await old.delete();
        await file.rename(old.path);
      }
      await file.writeAsString('${jsonEncode(event)}\n', mode: FileMode.append);
    });
    _tail = operation.catchError((Object _) {});
    return operation;
  }

  Future<String> export() async {
    await _tail;
    final path = '${directory.path}/diagnostic-events.json';
    await File(
      path,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(entries));
    return path;
  }
}

class ConfigStore {
  ConfigStore(this.file);
  final File file;
  Future<AppConfig> load() async => await file.exists()
      ? AppConfig.fromJson(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>,
        )
      : AppConfig();
  Future<void> save(AppConfig config) async {
    AppConfig.fromJson(config.toJson());
    await file.parent.create(recursive: true);
    final next = File('${file.path}.next');
    await next.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
      flush: true,
    );
    final backup = File('${file.path}.bak');
    if (await backup.exists()) await backup.delete();
    if (await file.exists()) await file.rename(backup.path);
    try {
      await next.rename(file.path);
    } catch (_) {
      if (await backup.exists()) await backup.rename(file.path);
      rethrow;
    }
  }
}
