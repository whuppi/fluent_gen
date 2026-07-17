// Tests for FluentFanOutBuilder.
//
// Uses a hand-rolled fake `PostProcessBuildStep` that records every
// write so the test asserts the output paths + content the builder
// produces. The interface is small enough that a fake beats a
// mocking library.

import 'dart:async';
import 'dart:convert';

import 'package:build/build.dart';
import 'package:crypto/crypto.dart';
import 'package:fluent_gen/src/builders/fan_out_builder.dart';
import 'package:test/test.dart';

void main() {
  group('FluentFanOutBuilder — input contract', () {
    test('declares the temp-json extension', () {
      const builder = FluentFanOutBuilder();
      expect(builder.inputExtensions, ['_fluent_gen_temp.json']);
    });
  });

  group('FluentFanOutBuilder — fan-out', () {
    test('writes one output per entry in the JSON map', () async {
      final step = _FakeStep(
        inputId: AssetId('demo', 'lib/_fluent_gen_temp.json'),
        contents: jsonEncode({
          'fluent_gen': {'version': 1},
          'outputs': {
            'lib/i18n/translations.g.dart': '// generated A\n',
            'lib/i18n/extras.g.dart': '// generated B\n',
          },
        }),
      );

      await const FluentFanOutBuilder().build(step);

      expect(step.writes, hasLength(2));
      expect(
        step.writes,
        containsPair(
          AssetId('demo', 'lib/i18n/translations.g.dart'),
          '// generated A\n',
        ),
      );
      expect(
        step.writes,
        containsPair(
          AssetId('demo', 'lib/i18n/extras.g.dart'),
          '// generated B\n',
        ),
      );
    });

    test('no outputs map → no writes (no-op)', () async {
      final step = _FakeStep(
        inputId: AssetId('demo', 'lib/_fluent_gen_temp.json'),
        contents: jsonEncode({
          'fluent_gen': {'version': 1, 'status': 'no-ftl-files'},
          'outputs': <String, String>{},
        }),
      );

      await const FluentFanOutBuilder().build(step);

      expect(step.writes, isEmpty);
    });

    test('missing outputs key → no writes', () async {
      // Defensive: the phase-1 builder always emits the `outputs`
      // key, but a corrupt cache might have an older payload. The
      // fan-out should treat missing `outputs` like an empty map.
      final step = _FakeStep(
        inputId: AssetId('demo', 'lib/_fluent_gen_temp.json'),
        contents: jsonEncode({
          'fluent_gen': {'version': 1},
        }),
      );

      await const FluentFanOutBuilder().build(step);

      expect(step.writes, isEmpty);
    });

    test('preserves the package id of the input', () async {
      // Outputs are written with the SAME package id as the input —
      // build_runner's contract for source emission. Writing to a
      // different package id would crash the post-process step's
      // `build_to: source` write.
      final step = _FakeStep(
        inputId: AssetId('myapp', 'lib/_fluent_gen_temp.json'),
        contents: jsonEncode({
          'fluent_gen': {'version': 1},
          'outputs': {'lib/i18n/m.g.dart': '// content\n'},
        }),
      );

      await const FluentFanOutBuilder().build(step);

      expect(step.writes.keys.single.package, 'myapp');
    });
  });
}

/// Minimal fake of `PostProcessBuildStep`. Records every write
/// against an in-memory map so the test can assert what was sent.
/// The build, digest, and readAsBytes methods are stubbed because
/// the fan-out builder only ever reads the input as a String.
class _FakeStep implements PostProcessBuildStep {
  _FakeStep({required this.inputId, required this.contents});

  @override
  final AssetId inputId;
  final String contents;

  final Map<AssetId, String> writes = {};

  @override
  Future<String> readInputAsString({Encoding encoding = utf8}) async =>
      contents;

  @override
  Future<List<int>> readInputAsBytes() async => utf8.encode(contents);

  @override
  Future<void> writeAsString(
    AssetId id,
    FutureOr<String> body, {
    Encoding encoding = utf8,
  }) async {
    writes[id] = await body;
  }

  @override
  Future<void> writeAsBytes(AssetId id, FutureOr<List<int>> bytes) async {
    writes[id] = utf8.decode(await bytes);
  }

  @override
  Future<Digest> digest(AssetId id) async => md5.convert([]);

  @override
  void deletePrimaryInput() {
    // Tests don't exercise input deletion. The fan-out builder
    // doesn't call this either; stub for the interface contract.
  }

  @override
  Future<void> complete() async {
    // No async cleanup needed for the in-memory fake.
  }
}
