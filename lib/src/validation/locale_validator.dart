// Validate non-base locales against the base locale.
//
// Localization is incremental work — translators ship coverage in
// pieces, and the build must NEVER block on partial translations.
// This validator surfaces drift as warnings only:
//
//   - missing message  (in base, absent from non-base)
//   - orphan message   (in non-base, absent from base)
//   - mismatched args  (same id, different variable set)
//
// The Builder layer logs each warning via package:build's `log.warning`
// which surfaces in build_runner's terminal output with a file:line
// pointer — same UX as analyzer warnings.

import 'package:fluent_gen/src/inspection/ftl_inspector.dart';
import 'package:fluent_gen/src/inference/inference.dart';

/// One discrepancy between a non-base locale and the base.
sealed class LocaleWarning {
  const LocaleWarning({required this.locale, required this.path});

  /// Locale tag of the file that triggered the warning.
  final String locale;

  /// Path of the file the warning concerns.
  final String path;

  /// Human-readable formatted message for the build log.
  String formatted();
}

/// A message defined in the base locale is absent from [locale].
class MissingMessageWarning extends LocaleWarning {
  /// Creates the warning for [messageId] missing from [locale].
  const MissingMessageWarning({
    required super.locale,
    required super.path,
    required this.messageId,
  });

  /// The base-locale message id that has no translation.
  final String messageId;

  @override
  String formatted() =>
      'fluent_gen: locale `$locale` is missing '
      'message `$messageId` (defined in the base locale). The '
      'generated accessor will fall back to the base-locale value '
      'or the literal id at runtime.';
}

/// A message in [locale] has no equivalent in the base locale.
class OrphanMessageWarning extends LocaleWarning {
  /// Creates the warning for the orphaned [messageId] in [locale].
  const OrphanMessageWarning({
    required super.locale,
    required super.path,
    required this.messageId,
  });

  /// The message id with no base-locale entry.
  final String messageId;

  @override
  String formatted() =>
      'fluent_gen: locale `$locale` defines '
      'message `$messageId` which has no equivalent in the base '
      'locale. Translators may have invented a key that the app '
      'never accesses; consider adding it to the base or removing '
      'it from `$locale`.';
}

/// The same message id uses a different variable set in [locale]
/// than in the base locale.
class ArgMismatchWarning extends LocaleWarning {
  /// Creates the warning comparing [baseArgs] against [localeArgs].
  const ArgMismatchWarning({
    required super.locale,
    required super.path,
    required this.messageId,
    required this.baseArgs,
    required this.localeArgs,
  });

  /// The message id whose variable sets diverge.
  final String messageId;

  /// Variable names the base locale's message uses (transitively).
  final Set<String> baseArgs;

  /// Variable names this locale's message uses (transitively).
  final Set<String> localeArgs;

  /// Variables only this locale uses.
  Set<String> get extraInLocale => localeArgs.difference(baseArgs);

  /// Base-locale variables this locale never uses.
  Set<String> get missingInLocale => baseArgs.difference(localeArgs);

  @override
  String formatted() {
    final parts = <String>[];
    if (extraInLocale.isNotEmpty) {
      parts.add(
        'extra args ${extraInLocale.map((a) => '`\$$a`').join(', ')} '
        'not declared by the base locale',
      );
    }
    if (missingInLocale.isNotEmpty) {
      parts.add(
        'missing args ${missingInLocale.map((a) => '`\$$a`').join(', ')} '
        'declared by the base locale',
      );
    }
    return 'fluent_gen: locale `$locale` has message '
        '`$messageId` with mismatched argument set: '
        '${parts.join('; ')}.';
  }
}

/// Validate every non-base-locale file against the merged base
/// locale, returning a list of warnings (empty when fully aligned).
///
/// Conventionally `baseFiles` is the slice of files belonging to
/// the configured `base_locale`; `nonBaseFiles` is everything else.
/// The caller groups files per their per-file or per-directory
/// locale convention before passing them in.
List<LocaleWarning> validateNonBaseLocales({
  required List<InspectedFile> baseFiles,
  required List<InspectedFile> nonBaseFiles,
  required bool warnOnMissingMessages,
  required bool warnOnOrphanMessages,
  required bool warnOnArgMismatch,
}) {
  // Build the base locale's index: messageId → set of variable
  // names. Inference is the source of truth for "what args does
  // this message take" — it walks the AST consistently with what
  // the generator would emit, INCLUDING transitive message
  // references, so the comparison sees the same arg sets consumers
  // must supply. Each locale resolves references within its own
  // message graph.
  final baseContext = _contextFor(baseFiles);
  final baseIndex = <String, Set<String>>{};
  for (final file in baseFiles) {
    for (final msg in file.messages) {
      baseIndex[msg.id] = _argNames(msg, baseContext);
    }
  }

  // Group non-base files per locale so each warning is reported
  // against the file that triggered it.
  final nonBaseByLocale = <String, List<InspectedFile>>{};
  for (final file in nonBaseFiles) {
    nonBaseByLocale.putIfAbsent(file.locale, () => []).add(file);
  }

  final warnings = <LocaleWarning>[];

  for (final entry in nonBaseByLocale.entries) {
    final locale = entry.key;
    final files = entry.value;

    final localeContext = _contextFor(files);
    final localeIndex = <String, ({Set<String> args, String path})>{};
    for (final file in files) {
      for (final msg in file.messages) {
        localeIndex[msg.id] = (
          args: _argNames(msg, localeContext),
          path: file.path,
        );
      }
    }

    if (warnOnMissingMessages) {
      for (final baseId in baseIndex.keys) {
        if (!localeIndex.containsKey(baseId)) {
          warnings.add(
            MissingMessageWarning(
              locale: locale,
              path: files.first.path,
              messageId: baseId,
            ),
          );
        }
      }
    }

    if (warnOnOrphanMessages) {
      for (final entry in localeIndex.entries) {
        if (!baseIndex.containsKey(entry.key)) {
          warnings.add(
            OrphanMessageWarning(
              locale: locale,
              path: entry.value.path,
              messageId: entry.key,
            ),
          );
        }
      }
    }

    if (warnOnArgMismatch) {
      for (final entry in localeIndex.entries) {
        final baseArgs = baseIndex[entry.key];
        if (baseArgs == null) continue; // orphan; already reported
        final localeArgs = entry.value.args;
        if (!_setEquals(baseArgs, localeArgs)) {
          warnings.add(
            ArgMismatchWarning(
              locale: locale,
              path: entry.value.path,
              messageId: entry.key,
              baseArgs: baseArgs,
              localeArgs: localeArgs,
            ),
          );
        }
      }
    }
  }

  return warnings;
}

InferenceContext _contextFor(List<InspectedFile> files) => InferenceContext(
  messagesById: {
    for (final file in files)
      for (final msg in file.messages) msg.id: msg.message,
  },
);

Set<String> _argNames(InspectedMessage msg, InferenceContext context) {
  final inferred = inferMessage(msg.message, context).messageVariables;
  return {for (final v in inferred) v.name};
}

bool _setEquals<T>(Set<T> a, Set<T> b) {
  if (a.length != b.length) return false;
  for (final x in a) {
    if (!b.contains(x)) return false;
  }
  return true;
}
