import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final project = Directory.current.absolute;

  group('native rendering boundary', () {
    test('production Dart contains no embedded-web surface or browser UI API', () {
      final lib = Directory(_join(project.path, 'lib'));
      expect(
        lib.existsSync(),
        isTrue,
        reason: 'Run this test from the Flutter project root.',
      );

      final violations = _scanTextFiles(
        project: project,
        files: _filesUnder(lib, const <String>{'.dart'}),
        forbidden: <String, RegExp>{
          'browser-only Dart or package import': RegExp(
            r'''(?:import|export)\s+['"](?:dart:(?:html|js|js_interop|js_util|ui_web)|package:(?:web|html|universal_html|flutter_web_plugins|flutter_html|flutter_widget_from_html|webf|[^/'"]*(?:webview|inappweb|chromium|cef)[^/'"]*)/)''',
            caseSensitive: false,
          ),
          'embedded browser widget or controller': RegExp(
            r'\b(?:HtmlElementView|WebView|WebViewWidget|WebViewController|WebViewEnvironment|InAppWebView|HeadlessInAppWebView|ChromiumWebBrowser)\b',
            caseSensitive: false,
          ),
          'embedded JavaScript execution': RegExp(
            r'\b(?:runJavaScript|runJavaScriptReturningResult|evaluateJavaScript|evaluateJavascript|executeScript)\s*\(',
            caseSensitive: false,
          ),
          'browser DOM access': RegExp(
            r'\b(?:document\.(?:createElement|querySelector)|window\.(?:open|document)|shadowRoot|customElements\.define)\b',
            caseSensitive: false,
          ),
          'inline browser document or script': RegExp(
            r'<\s*(?:!doctype\s+html|html\b|script\b|style\b)',
            caseSensitive: false,
          ),
        },
      );

      expect(
        violations,
        isEmpty,
        reason:
            'All app-owned UI must be implemented with Flutter/Dart/native '
            'Windows rendering, never an embedded browser surface.',
      );
    });

    test('direct runtime dependencies contain no browser-rendering package', () {
      final pubspec = File(_join(project.path, 'pubspec.yaml'));
      final lockfile = File(_join(project.path, 'pubspec.lock'));
      expect(pubspec.existsSync(), isTrue);
      expect(lockfile.existsSync(), isTrue);

      final declared = _directDependenciesFromPubspec(
        pubspec.readAsStringSync(),
      );
      final resolved = _directMainPackagesFromLock(lockfile.readAsStringSync());

      // These checks also make parser drift fail closed instead of silently
      // turning the policy guard into an empty scan.
      expect(declared, contains('flutter'));
      expect(resolved, contains('flutter'));

      final violations = <String>{
        ...declared,
        ...resolved,
      }.where(_isBrowserRenderingPackage).toList()..sort();

      expect(
        violations,
        isEmpty,
        reason:
            'Direct production dependencies may provide HTTP or external-browser '
            'launching, but may not render HTML, JavaScript, Chromium, or a WebView. '
            'Only direct runtime packages are checked here so Flutter test/dev-only '
            'transitive packages such as web and webdriver do not cause false positives.',
      );
    });

    test('Windows runner and plugin registration contain no embedded browser', () {
      final requiredIntegrationFiles = <File>[
        File(_join(project.path, 'windows', 'CMakeLists.txt')),
        File(_join(project.path, 'windows', 'flutter', 'CMakeLists.txt')),
        File(
          _join(
            project.path,
            'windows',
            'flutter',
            'generated_plugin_registrant.cc',
          ),
        ),
        File(
          _join(
            project.path,
            'windows',
            'flutter',
            'generated_plugin_registrant.h',
          ),
        ),
        File(
          _join(project.path, 'windows', 'flutter', 'generated_plugins.cmake'),
        ),
      ];
      final missing = requiredIntegrationFiles
          .where((file) => !file.existsSync())
          .map((file) => _relativePath(project, file))
          .toList();
      expect(
        missing,
        isEmpty,
        reason:
            'The committed Windows plugin integration must remain auditable.',
      );

      final runner = Directory(_join(project.path, 'windows', 'runner'));
      final windowsFiles = <File>{
        ...requiredIntegrationFiles,
        ..._filesUnder(runner, _windowsTextExtensions),
      };
      final violations = _scanTextFiles(
        project: project,
        files: windowsFiles,
        forbidden: <String, RegExp>{
          'WebView/WebView2 integration': RegExp(
            r'\b(?:WebView2|ICoreWebView2\w*|CoreWebView2\w*|CreateCoreWebView2\w*|WebView2Loader\w*|WebViewWidget|WebViewController|IWebBrowser2|WebBrowser)\b|Shell\.Explorer',
            caseSensitive: false,
          ),
          'Chromium/CEF integration': RegExp(
            r'\b(?:ChromiumWebBrowser|CefSharp|libcef|CefInitialize|CefExecuteProcess|CefBrowser|CefApp|CefSettings|embedded[ -]?chromium)\b',
            caseSensitive: false,
          ),
          'embedded-web Flutter plugin': RegExp(
            r'\b(?:[A-Za-z0-9_]*(?:webview|inappweb|chromium)[A-Za-z0-9_]*|flutter_cef(?:_[A-Za-z0-9_]+)?|webf(?:_plugin)?)\b',
            caseSensitive: false,
          ),
          'Microsoft embedded-web package': RegExp(
            r'Microsoft\.Web\.WebView2',
            caseSensitive: false,
          ),
        },
        forbiddenFileName: RegExp(
          r'(?:webview|chromium|cefsharp|libcef|electron)',
          caseSensitive: false,
        ),
      );
      violations.addAll(_windowsPluginMetadataViolations(project));
      violations.sort();

      expect(
        violations,
        isEmpty,
        reason:
            'The native Windows runner and generated plugin registration must '
            'host Flutter directly and must not link or register a browser engine.',
      );
    });

    test('shipped assets and platform roots contain no browser code', () {
      final pubspec = File(_join(project.path, 'pubspec.yaml'));
      final assetFiles = <File>{};
      final conventionalAssets = Directory(_join(project.path, 'assets'));
      assetFiles.addAll(_allFilesUnder(conventionalAssets));

      for (final declaredPath in _declaredAssetPaths(
        pubspec.readAsStringSync(),
      )) {
        final entityPath = _joinMany(project.path, _pathParts(declaredPath));
        final type = FileSystemEntity.typeSync(entityPath, followLinks: false);
        if (type == FileSystemEntityType.file) {
          assetFiles.add(File(entityPath));
        } else if (type == FileSystemEntityType.directory) {
          assetFiles.addAll(_allFilesUnder(Directory(entityPath)));
        }
      }

      final violations = assetFiles
          .where(
            (file) => _browserCodeExtensions.contains(_extension(file.path)),
          )
          .map((file) => '${_relativePath(project, file)}: browser-code asset')
          .toList();

      // A Flutter `web/` bootstrap is itself a browser-hosted application
      // surface, regardless of whether its files are declared as assets.
      final webRoot = Directory(_join(project.path, 'web'));
      violations.addAll(
        _allFilesUnder(webRoot).map(
          (file) => '${_relativePath(project, file)}: web platform surface',
        ),
      );
      violations.sort();

      expect(
        violations,
        isEmpty,
        reason:
            'Shipped app-owned assets may not contain HTML/CSS/JavaScript, '
            'WebAssembly, or a browser-platform application bootstrap.',
      );
    });
  });
}

const _windowsTextExtensions = <String>{
  '.cc',
  '.cmake',
  '.cpp',
  '.cs',
  '.def',
  '.h',
  '.hpp',
  '.idl',
  '.json',
  '.manifest',
  '.props',
  '.rc',
  '.targets',
  '.txt',
  '.xml',
};

const _browserCodeExtensions = <String>{
  '.cjs',
  '.css',
  '.htm',
  '.html',
  '.js',
  '.jsx',
  '.less',
  '.mjs',
  '.sass',
  '.scss',
  '.svelte',
  '.ts',
  '.tsx',
  '.vue',
  '.wasm',
  '.xhtml',
};

List<String> _scanTextFiles({
  required Directory project,
  required Iterable<File> files,
  required Map<String, RegExp> forbidden,
  RegExp? forbiddenFileName,
}) {
  final violations = <String>[];
  final sortedFiles = files.toSet().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in sortedFiles) {
    final relative = _relativePath(project, file);
    if (forbiddenFileName?.hasMatch(_fileName(file.path)) ?? false) {
      violations.add('$relative: forbidden embedded-browser filename');
    }

    final source = file.readAsStringSync();
    for (final entry in forbidden.entries) {
      if (entry.value.hasMatch(source)) {
        violations.add('$relative: ${entry.key}');
      }
    }
  }
  violations.sort();
  return violations;
}

Iterable<File> _filesUnder(
  Directory root,
  Set<String> allowedExtensions,
) sync* {
  for (final file in _allFilesUnder(root)) {
    if (allowedExtensions.contains(_extension(file.path))) yield file;
  }
}

Iterable<File> _allFilesUnder(Directory root) sync* {
  if (!root.existsSync()) return;
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is File) yield entity;
  }
}

Set<String> _directDependenciesFromPubspec(String source) {
  final dependencies = <String>{};
  var inDependencies = false;
  final topLevel = RegExp(r'^([A-Za-z_][A-Za-z0-9_-]*):');
  final dependency = RegExp(r'^ {2}([A-Za-z_][A-Za-z0-9_-]*):(?:\s|$)');

  for (final line in const LineSplitter().convert(source)) {
    final topLevelMatch = topLevel.firstMatch(line);
    if (topLevelMatch != null) {
      inDependencies = topLevelMatch.group(1) == 'dependencies';
      continue;
    }
    if (!inDependencies) continue;
    final dependencyMatch = dependency.firstMatch(line);
    if (dependencyMatch != null) dependencies.add(dependencyMatch.group(1)!);
  }
  return dependencies;
}

Set<String> _directMainPackagesFromLock(String source) {
  final dependencies = <String>{};
  final packageHeader = RegExp(r'^ {2}([A-Za-z_][A-Za-z0-9_-]*):\s*$');
  String? currentPackage;

  for (final line in const LineSplitter().convert(source)) {
    final packageMatch = packageHeader.firstMatch(line);
    if (packageMatch != null) {
      currentPackage = packageMatch.group(1);
      continue;
    }
    if (currentPackage == null || !line.startsWith('    dependency:')) {
      continue;
    }
    final value = line
        .substring(line.indexOf(':') + 1)
        .trim()
        .replaceAll('"', '')
        .replaceAll("'", '');
    if (value == 'direct main') dependencies.add(currentPackage);
  }
  return dependencies;
}

bool _isBrowserRenderingPackage(String package) {
  final normalized = package.toLowerCase().replaceAll('-', '_');
  if (const <String>{
    'web',
    'html',
    'universal_html',
    'flutter_web_plugins',
    'flutter_html',
    'flutter_widget_from_html',
    'webf',
    'flutter_js',
    'javascriptcore',
  }.contains(normalized)) {
    return true;
  }
  return normalized.contains('webview') ||
      normalized.contains('inappweb') ||
      normalized.contains('chromium') ||
      normalized == 'cef' ||
      normalized.startsWith('cef_') ||
      normalized.endsWith('_cef');
}

List<String> _windowsPluginMetadataViolations(Directory project) {
  final metadata = File(_join(project.path, '.flutter-plugins-dependencies'));
  if (!metadata.existsSync()) return const <String>[];

  final decoded = jsonDecode(metadata.readAsStringSync());
  if (decoded is! Map<String, dynamic>) {
    return const <String>[
      '.flutter-plugins-dependencies: unparseable plugin metadata',
    ];
  }
  final plugins = decoded['plugins'];
  if (plugins is! Map<String, dynamic>) return const <String>[];
  final windowsPlugins = plugins['windows'];
  if (windowsPlugins is! List<dynamic>) return const <String>[];

  final violations = <String>[];
  for (final plugin in windowsPlugins) {
    if (plugin is! Map<String, dynamic> || plugin['dev_dependency'] == true) {
      continue;
    }
    final name = plugin['name'];
    if (name is String && _isBrowserRenderingPackage(name)) {
      violations.add(
        '.flutter-plugins-dependencies: forbidden Windows plugin $name',
      );
    }
  }
  return violations;
}

Set<String> _declaredAssetPaths(String source) {
  final paths = <String>{};
  var inFlutter = false;
  var inAssets = false;
  var assetsIndent = -1;

  for (final line in const LineSplitter().convert(source)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final indent = line.length - line.trimLeft().length;

    if (indent == 0) {
      inFlutter = trimmed == 'flutter:';
      inAssets = false;
      continue;
    }
    if (!inFlutter) continue;
    if (!inAssets && trimmed == 'assets:') {
      inAssets = true;
      assetsIndent = indent;
      continue;
    }
    if (!inAssets) continue;
    if (indent <= assetsIndent) {
      inAssets = false;
      continue;
    }

    final item = RegExp(r'^-\s+(.+)$').firstMatch(trimmed);
    if (item == null) continue;
    var path = item.group(1)!.trim();
    if (path.startsWith('path:')) path = path.substring(5).trim();
    final comment = path.indexOf(' #');
    if (comment >= 0) path = path.substring(0, comment).trim();
    if ((path.startsWith('"') && path.endsWith('"')) ||
        (path.startsWith("'") && path.endsWith("'"))) {
      path = path.substring(1, path.length - 1);
    }
    if (path.isNotEmpty) paths.add(path);
  }
  return paths;
}

String _join(
  String first, [
  String? second,
  String? third,
  String? fourth,
  String? fifth,
]) {
  return <String?>[
    first,
    second,
    third,
    fourth,
    fifth,
  ].whereType<String>().join(Platform.pathSeparator);
}

String _joinMany(String first, Iterable<String> rest) {
  return <String>[first, ...rest].join(Platform.pathSeparator);
}

List<String> _pathParts(String path) {
  return path
      .replaceAll('\\', '/')
      .split('/')
      .where((part) => part.isNotEmpty)
      .toList();
}

String _relativePath(Directory project, File file) {
  final root = '${project.path}${Platform.pathSeparator}';
  final absolute = file.absolute.path;
  if (absolute.toLowerCase().startsWith(root.toLowerCase())) {
    return absolute.substring(root.length);
  }
  return absolute;
}

String _fileName(String path) {
  final slash = path.lastIndexOf(Platform.pathSeparator);
  return slash < 0 ? path : path.substring(slash + 1);
}

String _extension(String path) {
  final separator = path.lastIndexOf(Platform.pathSeparator);
  final dot = path.lastIndexOf('.');
  return dot <= separator ? '' : path.substring(dot).toLowerCase();
}
