// scripts/validate_markdown_links.dart
//
// Walks all *.md files in docs/, lib/**/CLAUDE.md, supabase/**/CLAUDE.md,
// .claude/skills/**/*.md and verifies that every [text](path) link's
// target file exists.
//
// Usage: dart run scripts/validate_markdown_links.dart
// Exit codes: 0 = all links resolve, 1 = broken links found.

import 'dart:io';

void main() {
  final root = Directory.current.path;
  final files = <File>[];
  for (final entry in Directory('docs').listSync(recursive: true)) {
    if (entry is File && entry.path.endsWith('.md')) files.add(entry);
  }
  for (final entry in Directory('.claude').listSync(recursive: true)) {
    if (entry is File && entry.path.endsWith('.md')) files.add(entry);
  }
  for (final entry in Directory('lib').listSync(recursive: true)) {
    if (entry is File && entry.path.endsWith('CLAUDE.md')) files.add(entry);
  }
  for (final entry in Directory('supabase').listSync(recursive: true)) {
    if (entry is File && entry.path.endsWith('CLAUDE.md')) files.add(entry);
  }
  files.add(File('CLAUDE.md'));

  final broken = <String>[];
  final linkRegex = RegExp(r'\[([^\]]*)\]\(([^)]+)\)');
  for (final f in files) {
    final content = f.readAsStringSync();
    for (final m in linkRegex.allMatches(content)) {
      final target = m.group(2)!;
      if (target.startsWith('http://') || target.startsWith('https://') || target.startsWith('#')) continue;
      // Resolve relative to the source file's directory.
      final sourceDir = File(f.path).parent.path;
      final targetPath = target.contains('#') ? target.split('#').first : target;
      final resolved = File('$sourceDir/$targetPath');
      // Also try root-relative resolution if not found.
      final rootResolved = File('$root/$targetPath');
      if (!resolved.existsSync() && !rootResolved.existsSync()) {
        broken.add('${f.path}: [${m.group(1)}](${target}) → not found');
      }
    }
  }

  if (broken.isNotEmpty) {
    stderr.writeln('Broken markdown links:');
    for (final b in broken) stderr.writeln('  - $b');
    exit(1);
  }
  stdout.writeln('All markdown links resolve. Checked ${files.length} files.');
}
