// Reads a JSON payload of the form `{outputs: {path: source}}` and
// writes each entry to its real source-tree path.
//
// Paired with the FTL → JSON Builder via `applies_builders` in
// `build.yaml`. Splitting the work is necessary because
// `Builder.buildExtensions` is a static map; consumer-configurable
// output paths can't be expressed there.

import 'dart:async';
import 'dart:convert';

import 'package:build/build.dart';

/// build_runner factory for [FluentFanOutBuilder].
PostProcessBuilder fluentFanOutBuilder(BuilderOptions options) =>
    const FluentFanOutBuilder();

/// Writes each `{path: source}` entry of the primary builder's JSON
/// payload to the consumer's source tree.
class FluentFanOutBuilder implements PostProcessBuilder {
  /// The builder is stateless — const-constructible.
  const FluentFanOutBuilder();

  @override
  Iterable<String> get inputExtensions => const ['_fluent_gen_temp.json'];

  @override
  Future<void> build(PostProcessBuildStep step) async {
    final raw = await step.readInputAsString();
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final outputs = (json['outputs'] as Map<String, dynamic>?) ?? const {};

    if (outputs.isEmpty) {
      // Empty `outputs` is a legitimate signal from the upstream
      // builder: nothing to write yet (no .ftl files, base locale
      // missing, etc.). The upstream stage already logged the
      // cause; do not re-log here.
      return;
    }

    for (final entry in outputs.entries) {
      final outputId = AssetId(step.inputId.package, entry.key);
      final content = entry.value as String;
      // Sequential writes keep memory bounded for large outputs.
      await step.writeAsString(outputId, content);
    }
  }
}
