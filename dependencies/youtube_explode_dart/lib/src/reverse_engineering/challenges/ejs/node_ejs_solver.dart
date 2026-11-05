import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'base_ejs_solver.dart';
import 'ejs.dart';

/// JS Challenge solver backed by local Node.js execution.
class NodeEJSSolver extends BaseEJSSolver {
  final String _nodeExe;
  final String _modules;
  final Directory tmpDir;

  NodeEJSSolver._(this._nodeExe, this._modules, this.tmpDir);

  /// Attempts to initialize NodeEJSSolver. Returns null if node is not installed or available on PATH.
  static Future<NodeEJSSolver?> tryInit({String nodeExe = 'node'}) async {
    try {
      final check = await Process.run(nodeExe, ['--version']);
      if (check.exitCode != 0) return null;

      final modules = await EJSBuilder.getJSModules();
      final tmp = await Directory.systemTemp.createTemp('sp_node_ejs_');
      return NodeEJSSolver._(nodeExe, modules, tmp);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String> executeJavaScript(String jsCode) async {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final scriptFile = File(path.join(tmpDir.path, 'eval_$timestamp.js'));
    final outFile = File(path.join(tmpDir.path, 'out_$timestamp.json'));
    final escapedOut = outFile.path.replaceAll(r'\', r'/');

    final runnerScript = '''
const fs = require('fs');
$_modules

try {
  const result = $jsCode;
  fs.writeFileSync("$escapedOut", typeof result === 'string' ? result : JSON.stringify(result));
} catch (err) {
  fs.writeFileSync("$escapedOut", JSON.stringify({ error: String(err) }));
}
''';

    await scriptFile.writeAsString(runnerScript);
    try {
      final pr = await Process.run(_nodeExe, [scriptFile.path]);
      if (!outFile.existsSync()) {
        throw Exception('Node.js evaluation failed: ${pr.stderr}');
      }
      return await outFile.readAsString();
    } finally {
      try {
        if (scriptFile.existsSync()) scriptFile.deleteSync();
        if (outFile.existsSync()) outFile.deleteSync();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    try {
      if (tmpDir.existsSync()) {
        tmpDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  }
}
