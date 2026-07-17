// Verify the generated `lib/i18n/app_messages.g.dart` is
// syntactically + semantically valid Dart. Plan.md §10.7 calls for
// this — without it, an emitter regression that produces invalid
// Dart could silently pass the contains-style emission tests AND
// the smoke test below (which only fails at compile time, not at
// emission time).
//
// The test shells out to `dart analyze` against the example's
// package directory and asserts a clean result. It assumes
// `dart run build_runner build` has already produced the
// generated file — typically true in CI ordering, and locally
// after the first build_runner run.

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'generated app_messages.g.dart analyzes clean',
    () async {
      final generated = File(
        '${Directory.current.path}/lib/i18n/app_messages.g.dart',
      );
      if (!generated.existsSync()) {
        fail(
          'Expected generated file at ${generated.path}. Run '
          '`dart run build_runner build --delete-conflicting-outputs` '
          'before running this test.',
        );
      }

      // Use `fvm dart analyze` indirectly: just run `dart` from the
      // shell PATH. The fvm wrapper sets up the right SDK at the
      // start of the dev session, so this resolves to the project's
      // pinned Dart.
      //
      // We point analyze at the package root (`.`) so the analyzer
      // resolves `package:fluent_gen_example/...` imports
      // correctly. Pointing at `lib/i18n/app_messages.g.dart`
      // directly hits the SDK-bug-62710 plugin issue documented in
      // workspace rules.
      final result = await Process.run('dart', [
        'analyze',
        '.',
      ], workingDirectory: Directory.current.path);

      final stdout = result.stdout.toString();
      final stderr = result.stderr.toString();

      if (result.exitCode != 0) {
        fail(
          'dart analyze on the example package failed with exit code '
          '${result.exitCode}.\n\nstdout:\n$stdout\n\nstderr:\n$stderr',
        );
      }

      // Defense-in-depth: assert the generated file is mentioned
      // nowhere in any error/warning lines. If analyze ever returns
      // exit 0 with non-fatal output that mentions our generated
      // file, we still want to know.
      expect(
        stdout,
        isNot(contains('app_messages.g.dart')),
        reason:
            'dart analyze surfaced something on the generated file:\n$stdout',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
