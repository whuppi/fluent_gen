/// Public entrypoints for build_runner.
///
/// Two factories:
///
///   * [fluentGenBuilder] reads `.ftl` assets, runs inference and
///     emission, and writes the result as a JSON payload to a
///     cached temp file.
///
///   * [fluentFanOutBuilder] reads that JSON and writes each
///     `{outputPath: source}` entry to the consumer's source tree.
///
/// The split exists because `Builder.buildExtensions` is a static
/// extension-to-extension map; the consumer-configurable
/// `output_path` cannot be expressed there. The fan-out step
/// translates the JSON to whatever path the consumer asked for.
library;

import 'package:build/build.dart';
import 'package:fluent_gen/src/builders/fan_out_builder.dart' as fan_out;
import 'package:fluent_gen/src/builders/gen_builder.dart';

/// Construct the FTL → JSON-payload Builder.
Builder fluentGenBuilder(BuilderOptions options) =>
    FluentGenBuilder.fromOptions(options);

/// Construct the JSON-payload → source-files PostProcessBuilder.
PostProcessBuilder fluentFanOutBuilder(BuilderOptions options) =>
    fan_out.fluentFanOutBuilder(options);
