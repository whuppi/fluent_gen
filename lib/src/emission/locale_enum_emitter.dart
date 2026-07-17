// Emit the locale enum — one value per discovered locale, with
// parse / negotiation members, plus (when `bundle_ftl` is on) the
// embedded FTL sources and a `load()` convenience.
//
// The enum is pure Dart (no Flutter): tag parsing and negotiation are
// useful to CLIs and servers too. UI wiring (context plumbing, widget
// rebuild on switch) is the fluent_flutter satellite's territory.

import 'package:fluent_gen/src/emission/identifier.dart';
import 'package:fluent_gen/src/inspection/ftl_inspector.dart';

/// One locale the enum will carry.
class LocaleEnumEntry {
  /// Pairs a locale [tag] with the [files] discovered for it.
  const LocaleEnumEntry({required this.tag, required this.files});

  /// The BCP47-ish tag as discovered (`en`, `en-US`, `zh-Hans-CN`).
  final String tag;

  /// The locale's inspected files, in discovery order. Only read when
  /// bundling is on.
  final List<InspectedFile> files;
}

/// The enum-value Dart name for a locale [tag] (`en-US` → `enUs`).
String localeEnumValueName(String tag) => sanitizeIdentifier(tag);

/// Render the locale enum declaration.
///
/// [entries] must be non-empty and pre-sorted (the emitter sorts tags
/// alphabetically so output is deterministic regardless of filesystem
/// order). [baseTag] names the generator's `base_locale` and MUST be
/// one of the entries. When [bundleFtl] is true each value also gets
/// its embedded `ftlSources` and a `load()` that builds a ready
/// [String]-typed bundle.
String emitLocaleEnum({
  required String enumName,
  required List<LocaleEnumEntry> entries,
  required String baseTag,
  required bool bundleFtl,
}) {
  final buf = StringBuffer();

  buf.writeln('/// Every locale the generator discovered under the FTL');
  buf.writeln('/// directory. Pure Dart — parse and negotiate locale tags');
  buf.writeln('/// without any UI framework.');
  buf.writeln('enum $enumName {');
  for (final entry in entries) {
    buf.writeln('  /// `${entry.tag}`.');
    buf.writeln("  ${localeEnumValueName(entry.tag)}('${entry.tag}'),");
  }
  buf.writeln(';');
  buf.writeln();
  buf.writeln('  const $enumName(this.languageTag);');
  buf.writeln();
  buf.writeln('  /// The locale tag as discovered from the FTL layout.');
  buf.writeln('  final String languageTag;');
  buf.writeln();
  buf.writeln("  /// The generator's base locale — codegen was driven by it,");
  buf.writeln('  /// so it is always fully covered.');
  buf.writeln(
    '  static const $enumName base = $enumName.${localeEnumValueName(baseTag)};',
  );
  buf.writeln();
  buf.writeln('  /// The value whose tag matches [tag] (case-insensitive),');
  buf.writeln('  /// or null.');
  buf.writeln('  static $enumName? tryParse(String tag) {');
  buf.writeln('    final lower = tag.toLowerCase();');
  buf.writeln('    for (final locale in values) {');
  buf.writeln('      if (locale.languageTag.toLowerCase() == lower) {');
  buf.writeln('        return locale;');
  buf.writeln('      }');
  buf.writeln('    }');
  buf.writeln('    return null;');
  buf.writeln('  }');
  buf.writeln();
  buf.writeln('  /// Best available match for a requested tag, resolved');
  buf.writeln("  /// through the family ladder (fluent_bundle's");
  buf.writeln('  /// `negotiateLocale`): exact match, then the tag');
  buf.writeln('  /// progressively truncated, then the most general');
  buf.writeln('  /// available tag sharing the requested language; then');
  buf.writeln('  /// [fallback], defaulting to [base].');
  buf.writeln('  static $enumName negotiate(');
  buf.writeln('    String requested, {');
  buf.writeln('    $enumName? fallback,');
  buf.writeln('  }) {');
  buf.writeln('    final match = negotiateLocale(');
  buf.writeln('      requested,');
  buf.writeln(
    '      available: [for (final locale in values) locale.languageTag],',
  );
  buf.writeln('    );');
  buf.writeln('    if (match == null) return fallback ?? base;');
  buf.writeln('    return tryParse(match) ?? fallback ?? base;');
  buf.writeln('  }');

  if (bundleFtl) {
    buf.writeln();
    buf.writeln("  /// This locale's embedded FTL sources, one per file, in");
    buf.writeln('  /// discovery order. Baked in at build time — no asset');
    buf.writeln('  /// pipeline, no async load.');
    buf.writeln('  List<String> get ftlSources => switch (this) {');
    for (final entry in entries) {
      final sources = entry.files
          .map((f) => '          ${_dartStringLiteral(f.content)},')
          .join('\n');
      buf.writeln(
        '        $enumName.${localeEnumValueName(entry.tag)} => const [',
      );
      buf.writeln(sources);
      buf.writeln('        ],');
    }
    buf.writeln('      };');
    buf.writeln();
    buf.writeln('  /// A ready bundle for this locale: every embedded source');
    buf.writeln('  /// added, formatting delegated to [backend] (pass an');
    buf.writeln('  /// `IcuBackend` / `IntlBackend` from a satellite package');
    buf.writeln('  /// for CLDR-aware output).');
    buf.writeln('  FluentBundle load({');
    buf.writeln('    FluentBackend backend = const FluentBackend(),');
    buf.writeln('  }) {');
    buf.writeln(
      '    final bundle = FluentBundle(languageTag, backend: backend);',
    );
    buf.writeln('    for (final source in ftlSources) {');
    buf.writeln('      bundle.addResource(source);');
    buf.writeln('    }');
    buf.writeln('    return bundle;');
    buf.writeln('  }');
  }

  buf.writeln('}');
  return buf.toString();
}

/// Render [content] as a Dart string literal that survives any FTL —
/// non-raw triple-quoted, with backslashes and dollars escaped so
/// placeables (`{ $x }`) never interpolate. Lone quotes are legal
/// inside a triple-quoted string (escaping them trips
/// `unnecessary_string_escapes`); only a RUN of three gets its last
/// quote escaped so the literal can't terminate early.
String _dartStringLiteral(String content) {
  var escaped = content
      .replaceAll(r'\', r'\\')
      .replaceAll(r'$', r'\$')
      .replaceAll("'''", r"''\'");
  // A trailing quote would merge with the closing ''' into a 4+ run
  // and terminate the literal early. A newline separator is invisible
  // to the FTL parser (resource-level trailing whitespace).
  if (escaped.endsWith("'")) escaped = '$escaped\n';
  return "'''\n$escaped'''";
}
