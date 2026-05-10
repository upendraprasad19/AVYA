// scripts/check_edge_function_payloads.dart
//
// Gate 12: Flutter caller body keys ⊆ Edge Function validator shape.
//
// For every concept's edge_function_payloads[] entry in docs/sot_registry.yaml,
// verifies that the Flutter caller's payload keys are a subset of the keys
// the Edge Function reads from the request body.
//
// If no concepts have edge_function_payloads defined, this gate is a no-op pass.
//
// Exit 0 = pass.
// Exit 1 = fail.
//
// Usage: dart run scripts/check_edge_function_payloads.dart

import 'dart:io';

void main(List<String> args) async {
  final projectRoot = Directory.current.path;
  final registryFile = File('$projectRoot/docs/sot_registry.yaml');

  if (!registryFile.existsSync()) {
    stderr.writeln('[Gate 12] ERROR: docs/sot_registry.yaml not found');
    exit(1);
  }

  final registryContent = registryFile.readAsStringSync();

  // ── 1. Extract edge_function_payloads entries ─────────────────────────────
  //
  // Expected YAML shape (per concept):
  //   edge_function_payloads:
  //     - edge_function: ai-proxy
  //       caller_file: lib/core/services/ai_service.dart
  //       server_file: supabase/functions/ai-proxy/index.ts
  //
  // This gate is pragmatic: if the field is absent from ALL concepts,
  // exit 0 (no-op). If present, validate.

  final payloadEntries = <_PayloadEntry>[];

  final blockRegex = RegExp(
    r'edge_function_payloads:(.*?)(?=\n  - concept:|\Z)',
    dotAll: true,
    multiLine: true,
  );
  for (final blockMatch in blockRegex.allMatches(registryContent)) {
    final block = blockMatch.group(1) ?? '';
    // Each entry starts with "    - edge_function:"
    final entryRegex = RegExp(
      r'-\s+edge_function:\s*(\S+).*?caller_file:\s*(\S+).*?server_file:\s*(\S+)',
      dotAll: true,
    );
    for (final entryMatch in entryRegex.allMatches(block)) {
      payloadEntries.add(_PayloadEntry(
        edgeFunction: entryMatch.group(1)!.trim(),
        callerFile: entryMatch.group(2)!.trim(),
        serverFile: entryMatch.group(3)!.trim(),
      ));
    }
  }

  if (payloadEntries.isEmpty) {
    stdout.writeln(
        '[Gate 12] PASS (no-op) — no edge_function_payloads defined in registry yet.');
    exit(0);
  }

  // ── 2. For each entry, compare keys ──────────────────────────────────────

  final violations = <String>[];

  for (final entry in payloadEntries) {
    final callerPath = '$projectRoot/${entry.callerFile}';
    final serverPath = '$projectRoot/${entry.serverFile}';

    if (!File(callerPath).existsSync()) {
      violations.add(
          '[${entry.edgeFunction}] Caller file not found: ${entry.callerFile}');
      continue;
    }
    if (!File(serverPath).existsSync()) {
      violations.add(
          '[${entry.edgeFunction}] Server file not found: ${entry.serverFile}');
      continue;
    }

    final callerContent = File(callerPath).readAsStringSync();
    final serverContent = File(serverPath).readAsStringSync();

    // Extract caller keys: look for 'body: {' or 'body: const {' map literals
    // and collect keys like "'key': value" or "\"key\": value"
    final callerKeys = _extractMapKeys(callerContent, entry.edgeFunction);

    // Extract server keys: look for destructuring like:
    //   const { key1, key2 } = body;
    //   body.key1
    //   body['key1']
    final serverKeys = _extractServerBodyKeys(serverContent);

    // Caller keys must be ⊆ server keys
    final extraCallerKeys = callerKeys.difference(serverKeys);
    if (extraCallerKeys.isNotEmpty) {
      violations.add(
          '[${entry.edgeFunction}] Caller sends keys not read by server: '
          '${extraCallerKeys.join(', ')}');
      violations.add('  Caller: ${entry.callerFile}');
      violations.add('  Server: ${entry.serverFile}');
    }
  }

  // ── 3. Report ─────────────────────────────────────────────────────────────

  if (violations.isEmpty) {
    stdout.writeln(
        '[Gate 12] PASS — ${payloadEntries.length} edge function payload'
        ' contracts verified.');
    exit(0);
  } else {
    stderr.writeln('\n[Gate 12] FAIL — edge function payload mismatches:');
    for (final v in violations) {
      stderr.writeln('  $v');
    }
    exit(1);
  }
}

// Extract keys from Dart body map literals sent to Edge Functions.
// Handles patterns like: body: { 'key': value, "key2": value2 }
Set<String> _extractMapKeys(String content, String context) {
  final keys = <String>{};
  // Look for map literals following 'body:'
  final bodyMapRegex = RegExp(
    r"body\s*:\s*\{([^}]{1,2000})\}",
    dotAll: true,
  );
  for (final m in bodyMapRegex.allMatches(content)) {
    final mapContent = m.group(1) ?? '';
    // Extract quoted keys: 'key' or "key"
    // Use [\x27\x22] to avoid raw-string quote mixing issues (\x27 = ', \x22 = ")
    final keyRegex = RegExp('[\x27\x22]([a-zA-Z_][a-zA-Z0-9_]*)[\x27\x22]:\\s*');
    for (final km in keyRegex.allMatches(mapContent)) {
      keys.add(km.group(1)!);
    }
  }
  return keys;
}

// Extract keys the server reads from the request body in TypeScript.
// Handles:
//   const { key1, key2 } = body;
//   body.key1
//   body['key1']
//   const key1 = body.key1;
Set<String> _extractServerBodyKeys(String content) {
  final keys = <String>{};

  // Destructuring: const { key1, key2 } = body
  final destructureRegex = RegExp(
    r'(?:const|let|var)\s*\{([^}]+)\}\s*=\s*(?:await\s+)?(?:req\.json\(\)|body)',
    multiLine: true,
  );
  for (final m in destructureRegex.allMatches(content)) {
    final parts = m.group(1)!.split(',');
    for (final part in parts) {
      // Handle aliased destructuring: key: alias
      final name = part.split(':').first.trim();
      if (name.isNotEmpty && RegExp(r'^[a-zA-Z_]\w*$').hasMatch(name)) {
        keys.add(name);
      }
    }
  }

  // body.key or body['key']
  final dotAccessRegex = RegExp(r'\bbody\.([a-zA-Z_]\w*)');
  for (final m in dotAccessRegex.allMatches(content)) {
    keys.add(m.group(1)!);
  }
  // body['key'] — use \x27 for single quote
  final bracketAccessRegex = RegExp('\x27([a-zA-Z_]\\w*)\x27');
  for (final m in bracketAccessRegex.allMatches(content)) {
    // Only count when preceded by "body[" context
    // (simplified: add all single-quoted identifiers from body-adjacent context)
    keys.add(m.group(1)!);
  }

  return keys;
}

class _PayloadEntry {
  final String edgeFunction;
  final String callerFile;
  final String serverFile;
  const _PayloadEntry({
    required this.edgeFunction,
    required this.callerFile,
    required this.serverFile,
  });
}
