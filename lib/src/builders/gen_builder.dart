// Reads `.ftl` assets, runs inference and emission, writes the
// result as a JSON payload `{outputs: {path: source}}` to a cached
// temp file. `FluentFanOutBuilder` (builders/fan_out_builder.dart)
// then translates that payload to real source-tree files.
//
// The split is required: `Builder.buildExtensions` is a static
// extension-to-extension map; consumer-configurable output paths
// cannot be expressed there. Do not collapse the two builders into
// one without understanding why.

import 'dart:async';
import 'dart:convert';

import 'package:build/build.dart';
import 'package:fluent_gen/src/discovery/asset_glob.dart';
import 'package:fluent_gen/src/config/config.dart';
import 'package:fluent_gen/src/emission/emitter.dart';
import 'package:fluent_gen/src/inspection/ftl_inspector.dart';
import 'package:fluent_gen/src/discovery/locale_discovery.dart';
import 'package:fluent_gen/src/validation/locale_validator.dart';

/// The primary builder: discovers `.ftl` assets, runs inference +
/// emission, and writes the JSON payload the fan-out builder consumes.
class FluentGenBuilder implements Builder {
  /// Prefer [FluentGenBuilder.fromOptions] — build_runner's entry.
  FluentGenBuilder({required this.config});

  /// build_runner factory: parses `BuilderOptions.config`.
  factory FluentGenBuilder.fromOptions(BuilderOptions options) {
    return FluentGenBuilder(config: Config.fromMap(options.config));
  }

  /// The consumer's parsed build.yaml options.
  final Config config;

  @override
  Map<String, List<String>> get buildExtensions => const {
    // Synthetic single-output pattern: build_runner runs `build`
    // once per package, not once per FTL input. The placeholder
    // is what build_runner tracks for caching; the real output
    // (the `.g.dart`) is written separately via `writeAsString`.
    r'$lib$': ['_fluent_gen_temp.json'],
  };

  @override
  Future<void> build(BuildStep step) async {
    // Discover .ftl assets. The glob shape lives in `ftlAssetGlob`
    // so the unit suite can probe it against representative paths.
    final ftlAssets =
        await step.findAssets(ftlAssetGlob(config.ftlDir)).toList();

    if (ftlAssets.isEmpty) {
      await _writeSyntheticPlaceholder(
        step,
        payload: {
          'fluent_gen': {
            'version': 1,
            'status': 'no-ftl-files',
            'ftl_dir': config.ftlDir,
          },
          'outputs': <String, String>{},
        },
      );
      log.info('fluent_gen: no .ftl files found under ${config.ftlDir}');
      return;
    }

    // Read content once up-front so the downstream stages operate
    // on plain tuples instead of asset ids.
    final assetTuples = <({String path, String content})>[];
    for (final asset in ftlAssets) {
      final content = await step.readAsString(asset);
      assetTuples.add((path: asset.path, content: content));
    }

    // Group by locale (per-file vs per-directory).
    final LocaleDiscoveryResult discovery;
    try {
      discovery = discoverLocales(ftlDir: config.ftlDir, assets: assetTuples);
    } on LocaleDiscoveryError catch (e) {
      log.severe(e.message);
      rethrow;
    }

    if (!discovery.locales.contains(config.baseLocale)) {
      log.severe(
        'fluent_gen: base_locale `${config.baseLocale}` has no '
        'matching .ftl file under ${config.ftlDir}. Found locales: '
        '${discovery.locales.join(', ')}.',
      );
      // Write the placeholder so build_runner's caching is
      // consistent. Emission is skipped because there is no
      // base-locale source to emit from.
      await _writeSyntheticPlaceholder(
        step,
        payload: {
          'fluent_gen': {
            'version': 1,
            'status': 'base-locale-missing',
            'base_locale': config.baseLocale,
            'found_locales': discovery.locales.toList(),
          },
          'outputs': <String, String>{},
        },
      );
      return;
    }

    // Parse + inspect every file.
    final inspectedByLocale = <String, List<InspectedFile>>{};
    for (final discoveredFile in discovery.files) {
      final inspected = inspectFtl(
        path: discoveredFile.path,
        locale: discoveredFile.locale,
        content: discoveredFile.content,
      );
      inspectedByLocale.putIfAbsent(inspected.locale, () => []).add(inspected);

      if (inspected.junk.isEmpty) continue;

      // Junk in the BASE locale fails the build: a junked message
      // silently vanishes from the generated class, and the base
      // locale is developer-owned — a parse error there is a bug,
      // not translator drift.
      if (inspected.locale == config.baseLocale) {
        final preview = inspected.junk.first.content.trim();
        final message =
            'fluent_gen: base locale '
            '`${config.baseLocale}` has ${inspected.junk.length} '
            'unparseable entry/entries in `${inspected.path}`. '
            'First: `${preview.length > 80 ? '${preview.substring(0, 80)}…' : preview}`. '
            'Fix the FTL — messages the parser cannot read are '
            'silently absent from the generated class.';
        log.severe(message);
        throw StateError(message);
      }

      // Non-base junk stays a warning — translations are incremental
      // and must never block the build.
      log.warning(
        'fluent_gen: ${inspected.junk.length} parse-junk '
        "entry/entries in `${inspected.path}`. The bundle won't "
        'know about these messages until the FTL is fixed.',
      );
    }

    final baseFiles = inspectedByLocale[config.baseLocale]!;
    final nonBaseFiles = [
      for (final entry in inspectedByLocale.entries)
        if (entry.key != config.baseLocale) ...entry.value,
    ];

    // Validate non-base locales.
    final warnings = validateNonBaseLocales(
      baseFiles: baseFiles,
      nonBaseFiles: nonBaseFiles,
      warnOnMissingMessages: config.warnOnMissingMessages,
      warnOnOrphanMessages: config.warnOnOrphanMessages,
      warnOnArgMismatch: true,
    );
    for (final warn in warnings) {
      log.warning(warn.formatted());
    }

    // Emit the typed Dart file.
    final EmitResult emitted;
    try {
      emitted = emitFile(
        baseLocaleFiles: baseFiles,
        className: config.className,
        baseLocale: config.baseLocale,
        allLocaleFiles: inspectedByLocale,
        bundleFtl: config.bundleFtl,
        localeEnumName: config.localeEnumName,
      );
    } catch (e, st) {
      log.severe('fluent_gen: emission failed: $e\n$st');
      rethrow;
    }
    for (final note in emitted.notes) {
      log.warning(note.formatted());
    }

    // Pack the emission into the temp payload. The fan-out
    // PostProcessBuilder consumes this and writes the real source
    // files to `config.outputPath`.
    await _writeSyntheticPlaceholder(
      step,
      payload: {
        'fluent_gen': {
          'version': 1,
          'status': 'ok',
          'base_locale': config.baseLocale,
          'base_files': baseFiles.length,
          'non_base_files': nonBaseFiles.length,
          'warnings': warnings.length,
          'output': config.outputPath,
        },
        'outputs': {config.outputPath: emitted.source},
      },
    );

    log.info(
      'fluent_gen: emitted ${baseFiles.length} base-locale '
      'file(s) → `${config.outputPath}` '
      '(${nonBaseFiles.length} non-base file(s) validated, '
      '${warnings.length} warning(s)).',
    );
  }

  Future<void> _writeSyntheticPlaceholder(
    BuildStep step, {
    required Map<String, Object?> payload,
  }) async {
    // The asset id MUST match the `buildExtensions` declaration:
    // the `$lib$` → `_fluent_gen_temp.json` mapping resolves to
    // `lib/_fluent_gen_temp.json` in the consumer's package.
    // Changing this path without updating `buildExtensions` makes
    // build_runner reject the output as undeclared.
    final tempId = AssetId(step.inputId.package, 'lib/_fluent_gen_temp.json');
    await step.writeAsString(tempId, jsonEncode(payload));
  }
}
