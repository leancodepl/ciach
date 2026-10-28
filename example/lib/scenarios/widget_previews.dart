// Flutter widget previews, with Flutter-free stand-ins for `Preview` and
// `MultiPreview` from `package:flutter/widget_previews.dart`. ciach matches
// the annotation classes by name, so the stand-ins have the same names.
// Expected findings: `notAPreview`, `constantPreview` and `deprecatedPreview`,
// which no preview annotation marks, `preview`, which only `constantPreview`
// uses, `Gallery.new` and `Gallery.helper`, and the `Story` declarations. With
// an `{annotation: Story}` rule, `storyCard` and `darkStoryCard` are kept, and
// so are the `Story` and `DarkStory` classes that they use.
//
// Scanned only by the dedicated tests; see
// test/finder/widget_previews_test.dart.

/// Stand-in for Flutter's `Preview`.
base class Preview {
  const Preview();
}

/// Stand-in for Flutter's `MultiPreview`.
abstract base class MultiPreview {
  const MultiPreview();
}

/// A preview annotation of the project's own.
final class DarkPreview extends Preview {
  const DarkPreview();
}

/// A subclass of a subclass of `Preview`.
final class DarkerPreview extends DarkPreview {
  const DarkerPreview();
}

final class ThemePreviews extends MultiPreview {
  const ThemePreviews();
}

/// A class that implements `Preview` instead of extending it.
final class PreviewLike implements Preview {
  const PreviewLike();
}

/// Not a constructor call, so `flutter widget-preview` doesn't show what it
/// annotates.
const preview = Preview();

@Preview()
String primaryButtonPreview() => 'OK';

@DarkPreview()
String darkButtonPreview() => 'OK';

@DarkerPreview()
String darkerButtonPreview() => 'OK';

@ThemePreviews()
String themedButtonPreview() => 'OK';

@PreviewLike()
String likeButtonPreview() => 'OK';

@preview
String constantPreview() => 'OK';

@Deprecated('Use primaryButtonPreview.')
String deprecatedPreview() => 'OK';

String notAPreview() => 'OK';

/// Previews can be static methods and constructors. Each keeps the class.
class Gallery {
  const Gallery();

  @Preview()
  const Gallery.preview();

  @Preview()
  static String buttonPreview() => 'OK';

  static String helper() => 'OK';
}

/// An annotation class that the `{annotation: Story}` rule names.
class Story {
  const Story();
}

class DarkStory extends Story {
  const DarkStory();
}

@Story()
String storyCard() => 'OK';

@DarkStory()
String darkStoryCard() => 'OK';
