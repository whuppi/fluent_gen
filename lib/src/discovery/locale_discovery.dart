// Discover .ftl files under the configured directory and group them
// by locale.
//
// Two file-naming patterns are supported (both common in the i18n
// ecosystem). Within a single project, exactly one pattern must be
// used — mixing them is a build error because the locale-extraction
// rule would be ambiguous.
//
//   1. Per-file:  lib/i18n/en.ftl, lib/i18n/fr.ftl, lib/i18n/zh-CN.ftl
//      Locale = filename without `.ftl`.
//
//   2. Per-directory: lib/i18n/en/messages.ftl, lib/i18n/fr/messages.ftl
//      Locale = parent directory name.
//
// The walker takes a list of (path, content) tuples — it doesn't
// touch the filesystem itself. That keeps it pure and testable; the
// Builder layer hands it the assets `BuildStep.findAssets` returned.

import 'package:path/path.dart' as p;

/// One FTL source file paired with its discovered locale.
class DiscoveredLocaleFile {
  /// Pairs a file with its extracted locale.
  const DiscoveredLocaleFile({
    required this.path,
    required this.locale,
    required this.content,
  });

  /// Absolute or workspace-relative path the asset came from. Used
  /// for diagnostics; never for re-reading.
  final String path;

  /// The locale extracted from the path per the active pattern.
  final String locale;

  /// Raw `.ftl` source.
  final String content;

  @override
  String toString() => 'DiscoveredLocaleFile($locale @ $path)';
}

/// Result of [discoverLocales].
class LocaleDiscoveryResult {
  /// Bundles the detected [pattern] and grouped [files].
  const LocaleDiscoveryResult({required this.pattern, required this.files});

  /// Which file-naming pattern was detected.
  final LocaleNamingPattern pattern;

  /// All discovered `.ftl` files with their locales.
  final List<DiscoveredLocaleFile> files;

  /// Set of every locale that has at least one file.
  Set<String> get locales => {for (final f in files) f.locale};

  /// Files belonging to a specific locale (in input order).
  List<DiscoveredLocaleFile> filesFor(String locale) =>
      files.where((f) => f.locale == locale).toList(growable: false);
}

/// Which file-naming pattern the project uses.
enum LocaleNamingPattern {
  /// `lib/i18n/en.ftl` — locale lives in the filename.
  perFile,

  /// `lib/i18n/en/messages.ftl` — locale is the parent directory.
  perDirectory,

  /// No FTL files found. Caller decides whether to error or no-op.
  empty,
}

/// Thrown by [discoverLocales] when the input is structurally
/// invalid (mixed patterns, malformed locale tags, etc.). Build-time
/// only; never at runtime.
class LocaleDiscoveryError implements Exception {
  /// Creates the error with the consumer-facing [message].
  LocaleDiscoveryError(this.message);

  /// Names the offending path and the accepted layouts.
  final String message;

  @override
  String toString() => 'LocaleDiscoveryError: $message';
}

/// Walk a list of (path, content) tuples and group them by locale.
///
/// `ftlDir` is the configured root directory (e.g. `lib/i18n`); paths
/// are interpreted relative to it. The pattern detection looks at
/// the first non-config asset's path:
///
///   * If the file's name (without the `.ftl` extension) is a valid
///     locale tag → per-file pattern.
///   * Else if the file's parent directory name is a valid locale
///     tag → per-directory pattern.
///   * Else → error.
///
/// Once a pattern is chosen from the first asset, every other asset
/// MUST conform. Mixing produces [LocaleDiscoveryError].
LocaleDiscoveryResult discoverLocales({
  required String ftlDir,
  required List<({String path, String content})> assets,
}) {
  if (assets.isEmpty) {
    return const LocaleDiscoveryResult(
      pattern: LocaleNamingPattern.empty,
      files: [],
    );
  }

  // Detect the pattern from the first asset. The detection is a
  // pure function of the path, so the order of `assets` doesn't
  // matter — every asset gets re-classified against the chosen
  // pattern in the loop below.
  final firstRelative = _relativeTo(ftlDir, assets.first.path);
  final pattern = _detectPattern(firstRelative);

  if (pattern == LocaleNamingPattern.empty) {
    throw LocaleDiscoveryError(
      'Could not extract a locale from `${assets.first.path}`. '
      'Use either `$ftlDir/<locale>.ftl` (per-file) or '
      '`$ftlDir/<locale>/<name>.ftl` (per-directory).',
    );
  }

  final discovered = <DiscoveredLocaleFile>[];
  for (final asset in assets) {
    final relative = _relativeTo(ftlDir, asset.path);
    final assetPattern = _detectPattern(relative);
    if (assetPattern != pattern) {
      throw LocaleDiscoveryError(
        'Mixed locale-file patterns detected. '
        '`${assets.first.path}` looks like ${pattern.name}, '
        'but `${asset.path}` looks like ${assetPattern.name}. '
        'Pick one pattern and use it for every .ftl file.',
      );
    }

    final locale = _localeFor(pattern, relative);
    if (!isValidLocaleTag(locale)) {
      throw LocaleDiscoveryError(
        'Extracted locale `$locale` from `${asset.path}` is not a '
        'valid locale tag. Use BCP47-style tags like `en`, `en-US`, '
        'or `zh-Hans-CN`.',
      );
    }

    discovered.add(
      DiscoveredLocaleFile(
        path: asset.path,
        locale: locale,
        content: asset.content,
      ),
    );
  }

  return LocaleDiscoveryResult(pattern: pattern, files: discovered);
}

/// Strip the `ftlDir` prefix from a path so the remainder is
/// purely the in-i18n-tree portion.
String _relativeTo(String ftlDir, String fullPath) {
  // package:build asset paths use forward slashes on every
  // platform — no Windows-separator normalization needed.
  final normalizedDir = ftlDir.endsWith('/') ? ftlDir : '$ftlDir/';
  final idx = fullPath.indexOf(normalizedDir);
  if (idx == -1) {
    // Asset isn't inside the configured ftlDir. Return the path
    // unchanged; pattern detection will likely fail and produce a
    // clear error.
    return fullPath;
  }
  return fullPath.substring(idx + normalizedDir.length);
}

/// Detect the pattern from a single relative path.
///
///   `en.ftl`            → perFile
///   `en/messages.ftl`   → perDirectory
///   `nested/foo/x.ftl`  → empty (deeper than perDirectory; reject)
///   `something.ftl`     → empty if `something` isn't a locale tag
LocaleNamingPattern _detectPattern(String relativePath) {
  final segments = p.posix.split(relativePath);
  if (segments.length == 1) {
    // Just a filename. Check if its stem is a locale tag.
    final stem = p.posix.basenameWithoutExtension(segments.first);
    return isValidLocaleTag(stem)
        ? LocaleNamingPattern.perFile
        : LocaleNamingPattern.empty;
  }
  if (segments.length == 2) {
    // dir/file.ftl. Check if the dir is a locale tag.
    return isValidLocaleTag(segments.first)
        ? LocaleNamingPattern.perDirectory
        : LocaleNamingPattern.empty;
  }
  // Deeper than 2 segments is ambiguous: locale from arbitrary
  // depth could mean any of the parent directories. Detection
  // fails; the caller reports the offending path.
  return LocaleNamingPattern.empty;
}

String _localeFor(LocaleNamingPattern pattern, String relativePath) {
  final segments = p.posix.split(relativePath);
  return switch (pattern) {
    LocaleNamingPattern.perFile => p.posix.basenameWithoutExtension(
      segments.first,
    ),
    LocaleNamingPattern.perDirectory => segments.first,
    LocaleNamingPattern.empty =>
      throw StateError('cannot extract locale from empty pattern'),
  };
}

/// Strict-enough BCP47-ish check for distinguishing locale tags
/// from random filenames in directory walking. Also the rule
/// `Config` applies to consumer-supplied `base_locale` values — one
/// function, so the two can never disagree.
///
/// Accepted shape: 2-3 alpha characters (the ISO 639 language code),
/// optionally followed by hyphenated subtags like `-Hans`, `-CN`, or
/// `-u-ca-japanese`. Each subtag is itself alphanumeric.
///
///   en           → yes
///   en-US        → yes
///   zh-Hans-CN   → yes
///   ja-u-ca-jp   → yes
///   messages     → no  (more than 3 alpha chars, no hyphen)
///   common       → no
///
bool isValidLocaleTag(String tag) {
  if (tag.isEmpty) return false;
  // Language code: 2-3 alpha chars. Optional subtag chain: each
  // begins with a hyphen and is 1-8 alphanumeric chars.
  final pattern = RegExp(r'^[A-Za-z]{2,3}(-[A-Za-z0-9]{1,8})*$');
  return pattern.hasMatch(tag);
}
