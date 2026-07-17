// The dead-translation check, exactly as a consumer would run it:
// feed the generated manifest to the fluent_gen test helper and fail
// on any accessor nothing references. The example's tests use every
// message, so the set is empty — and stays empty, because adding an
// FTL message without using it turns this red.

import 'package:fluent_gen/testing.dart';
import 'package:fluent_gen_example/i18n/app_messages.g.dart';
import 'package:test/test.dart';

void main() {
  test('no dead translations', () {
    expect(
      unusedFluentAccessors(
        accessorNames: AppMessages.accessorNames,
        generatedFilePath: 'lib/i18n/app_messages.g.dart',
        // The example's only "app code" is its test suite — a real app
        // passes the default `lib`.
        sourceRoot: 'test',
      ),
      isEmpty,
    );
  });
}
