// Builds the asset-discovery glob the Builder uses for findAssets.
//
// Lives in its own file so the unit suite can probe the glob shape
// against representative paths — without it, a regression to a
// glob like `**/$ftlDir/**/*.ftl` (which silently fails to match
// single-segment-prefix paths) could ship without a red light.

import 'package:glob/glob.dart';

/// Build the [Glob] that walks every `.ftl` file under [ftlDir],
/// matching both per-file and per-directory locale layouts.
///
/// Shape rationale (verified by `test/asset_glob_test.dart`):
///
///   * `<ftlDir>/**.ftl`           — matches both layouts (used)
///   * `**/<ftlDir>/**/*.ftl`      — fails for paths that begin at
///                                    `<ftlDir>` with no preceding
///                                    segments (the common case)
///   * `<ftlDir>/**/*.ftl`         — fails for direct children
///   * `<ftlDir>/*.ftl`            — fails for nested directories
Glob ftlAssetGlob(String ftlDir) => Glob('$ftlDir/**.ftl');
