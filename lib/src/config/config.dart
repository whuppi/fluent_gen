// Parsed configuration for the fluent_gen Builder.
//
// Reads the merged map build_runner hands to the builder factory
// (`BuilderOptions.config`) and produces a typed [Config]. Validates
// required fields, applies defaults, surfaces clear errors when the
// consumer's build.yaml is malformed.

import 'package:fluent_gen/src/discovery/locale_discovery.dart'
    show isValidLocaleTag;

/// Configuration shape consumers pass under
/// `targets.$default.builders.fluent_gen.options` in their
/// `build.yaml`.
///
/// ```yaml
/// targets:
///   $default:
///     builders:
///       fluent_gen:fluent_gen:
///         options:
///           base_locale: en
///           ftl_dir: lib/i18n
///           class_name: Translations
///           output_path: lib/i18n/translations.g.dart
///           warn_on_missing_messages: true
///           warn_on_orphan_messages: true
///           locale_enum_name: AppLocale
///           bundle_ftl: false
/// ```
///
/// Every key has a documented default — only `base_locale` is
/// strictly required because there is no defensible default for it
/// (English isn't always the source language).
class Config {
  /// Prefer [Config.fromMap] — it applies defaults and validation.
  const Config({
    required this.baseLocale,
    required this.ftlDir,
    required this.outputPath,
    required this.className,
    required this.warnOnMissingMessages,
    required this.warnOnOrphanMessages,
    required this.localeEnumName,
    required this.bundleFtl,
  });

  /// Parse a [Config] from the raw `BuilderOptions.config` map.
  ///
  /// Throws [ConfigError] when a required key is missing or a
  /// supplied value has the wrong type. The error message includes
  /// the offending key so consumers can fix their `build.yaml`
  /// without spelunking.
  factory Config.fromMap(Map<String, dynamic> raw) {
    final baseLocale = _readRequiredString(raw, 'base_locale');
    final ftlDir = _readOptionalString(raw, 'ftl_dir') ?? 'lib/i18n';
    final outputPath =
        _readOptionalString(raw, 'output_path') ??
        '$ftlDir/translations.g.dart';
    final className = _readOptionalString(raw, 'class_name') ?? 'Translations';
    final warnMissing =
        _readOptionalBool(raw, 'warn_on_missing_messages') ?? true;
    final warnOrphan =
        _readOptionalBool(raw, 'warn_on_orphan_messages') ?? true;
    final localeEnumName =
        _readOptionalString(raw, 'locale_enum_name') ?? 'AppLocale';
    final bundleFtl = _readOptionalBool(raw, 'bundle_ftl') ?? false;

    _validateTypeName('class_name', className);
    _validateBaseLocale(baseLocale);
    _validateTypeName('locale_enum_name', localeEnumName);
    if (localeEnumName == className) {
      throw ConfigError(
        'locale_enum_name and class_name are both `$className` — the '
        'generated enum and class share one file and need distinct '
        'names.',
      );
    }

    return Config(
      baseLocale: baseLocale,
      ftlDir: ftlDir,
      outputPath: outputPath,
      className: className,
      warnOnMissingMessages: warnMissing,
      warnOnOrphanMessages: warnOrphan,
      localeEnumName: localeEnumName,
      bundleFtl: bundleFtl,
    );
  }

  /// The locale that drives codegen. Every other locale is validated
  /// against this one's message ids and arg shapes.
  final String baseLocale;

  /// Directory under the consumer's package containing `.ftl` files.
  /// Walked recursively. Either per-file pattern (`en.ftl`) or
  /// per-directory pattern (`en/messages.ftl`) — the discovery stage
  /// detects which is in use.
  final String ftlDir;

  /// Where to write the generated `.g.dart`.
  final String outputPath;

  /// Name of the generated accessor class.
  final String className;

  /// When true, missing messages in non-base locales emit build
  /// warnings (never errors).
  final bool warnOnMissingMessages;

  /// When true, messages that exist in a non-base locale but have no
  /// equivalent in the base emit build warnings.
  final bool warnOnOrphanMessages;

  /// Name of the generated locale enum (one value per discovered
  /// locale, with `tryParse` / `negotiate` / the base-locale constant).
  final String localeEnumName;

  /// When true, every locale's FTL source is embedded in the generated
  /// file and each enum value gains `ftlSources` + `load()` — no asset
  /// pipeline needed. Off by default: runtime asset loading keeps
  /// translations updatable without a rebuild.
  final bool bundleFtl;

  @override
  String toString() =>
      'Config('
      'baseLocale: $baseLocale, '
      'ftlDir: $ftlDir, '
      'outputPath: $outputPath, '
      'className: $className, '
      'warnOnMissingMessages: $warnOnMissingMessages, '
      'warnOnOrphanMessages: $warnOnOrphanMessages, '
      'localeEnumName: $localeEnumName, '
      'bundleFtl: $bundleFtl)';
}

/// Thrown by [Config.fromMap] when the consumer's `build.yaml`
/// contains a malformed value or omits a required key. The message
/// names the offending key so the consumer can fix it directly.
class ConfigError implements Exception {
  /// Creates the error with the consumer-facing [message].
  ConfigError(this.message);

  /// Names the offending build.yaml key and how to fix it.
  final String message;

  @override
  String toString() => 'ConfigError: $message';
}

String _readRequiredString(Map<String, dynamic> raw, String key) {
  final value = raw[key];
  if (value == null) {
    throw ConfigError(
      'Missing required option `$key` in fluent_gen config. '
      'Add it to your build.yaml under '
      '`targets.\$default.builders.fluent_gen.options.$key`.',
    );
  }
  if (value is! String) {
    throw ConfigError(
      'Option `$key` must be a string, got ${value.runtimeType}.',
    );
  }
  if (value.trim().isEmpty) {
    throw ConfigError('Option `$key` must not be empty.');
  }
  return value;
}

String? _readOptionalString(Map<String, dynamic> raw, String key) {
  final value = raw[key];
  if (value == null) return null;
  if (value is! String) {
    throw ConfigError(
      'Option `$key` must be a string, got ${value.runtimeType}.',
    );
  }
  return value;
}

bool? _readOptionalBool(Map<String, dynamic> raw, String key) {
  final value = raw[key];
  if (value == null) return null;
  if (value is! bool) {
    throw ConfigError(
      'Option `$key` must be a bool, got ${value.runtimeType}.',
    );
  }
  return value;
}

/// `class_name` and `locale_enum_name` land in generated Dart as
/// public type declarations. Reject anything that isn't a valid Dart
/// type identifier up front — every other emission step assumes this
/// passed. [key] names the offending build.yaml option in the error.
void _validateTypeName(String key, String name) {
  // A Dart identifier matches /[a-zA-Z_$][a-zA-Z0-9_$]*/. The
  // first character is required to be uppercase because Dart
  // conventions reserve lowercase identifiers for non-type names
  // and the analyzer would warn either way.
  final pattern = RegExp(r'^[A-Z][a-zA-Z0-9_$]*$');
  if (!pattern.hasMatch(name)) {
    throw ConfigError(
      '$key `$name` is not a valid Dart type identifier '
      '(must match /[A-Z][a-zA-Z0-9_\$]*/). Pick something like '
      '`Translations` or `AppMessages`.',
    );
  }
}

/// Locales are BCP47-ish strings (`en`, `en-US`, `zh-Hans-CN`).
/// The rule is [isValidLocaleTag] — the SAME function the
/// locale-discovery walker applies, so a walkable directory's locale
/// can always be supplied as `base_locale`.
void _validateBaseLocale(String locale) {
  if (!isValidLocaleTag(locale)) {
    throw ConfigError(
      'base_locale `$locale` is not a valid locale tag. '
      'Use something like `en`, `en-US`, or `zh-Hans-CN`.',
    );
  }
}
