import 'dart:convert';
import 'package:flutter/services.dart';

class ServerProfile {
  ServerProfile(this.id, this.language, this.timeZone, this.packages);
  final String id, language, timeZone;
  final Map<String, String?> packages;
  static Future<ServerProfile> load(String id) async {
    if (id != 'cn') throw UnsupportedError('该区服尚未适配');
    final data =
        jsonDecode(await rootBundle.loadString('resources/servers/$id.json'))
            as Map<String, dynamic>;
    if (data['schemaVersion'] != 1) throw const FormatException('区服资源版本不兼容');
    return ServerProfile(
      data['id'] as String,
      data['language'] as String,
      data['timeZone'] as String,
      {
        for (final c in data['channels'] as List)
          c['id'] as String: c['packageName'] as String?,
      },
    );
  }

  String packageFor(String channel) {
    final package = packages[channel];
    if (package == null) throw UnsupportedError('该渠道尚未完成包名与资源验证');
    return package;
  }
}
