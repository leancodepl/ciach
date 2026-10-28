// Entry points that an annotation marks. Expected findings: everything, by
// default. With an `{annotation: Story}` rule, only `notAStory`,
// `constantStory`, `deprecatedStory`, `Gallery.new`, `Gallery.helper` and
// `story`, which only `constantStory` uses.
//
// Scanned only by the dedicated tests; see
// test/finder/annotation_entry_points_test.dart.

/// The annotation class that the `{annotation: Story}` rule names. The rule
/// leaves out the type parameter.
class Story<T> {
  const Story();

  const Story.named();
}

class DarkStory extends Story<int> {
  const DarkStory();
}

/// A subclass of a subclass of `Story`.
class DarkerStory extends DarkStory {
  const DarkerStory();
}

/// A class that implements `Story` instead of extending it.
class StoryLike implements Story<String> {
  const StoryLike();
}

/// Not a constructor call, so it marks nothing.
const story = Story<int>();

@Story<int>()
String storyCard() => 'OK';

@Story<int>.named()
String namedStoryCard() => 'OK';

@DarkStory()
String darkStoryCard() => 'OK';

@DarkerStory()
String darkerStoryCard() => 'OK';

@StoryLike()
String likeStoryCard() => 'OK';

@story
String constantStory() => 'OK';

@Deprecated('Use storyCard.')
String deprecatedStory() => 'OK';

String notAStory() => 'OK';

/// Static methods and constructors can be marked too. Each keeps the class.
class Gallery {
  const Gallery();

  @Story<int>()
  const Gallery.card();

  @Story<int>()
  static String buttonCard() => 'OK';

  static String helper() => 'OK';
}
