/// Wraps [body] in a fence long enough to survive its own content.
///
/// A log message or response body can itself contain a ``` fence (LLM output,
/// CMS content, a pasted snippet). With a fixed 3-backtick fence that closes
/// the block early and leaks the payload into the rendered Markdown — and an
/// odd number of fences swallows every heading that follows. CommonMark says
/// the fence must be longer than any backtick run inside it, so measure first.
String fencedBlock(String body) {
  final text = body.trimRight();
  final fence = '`' * _delimiterLength(text, min: 3);
  return '$fence\n$text\n$fence\n';
}

/// Wraps [text] in an inline code span long enough to survive its own
/// backticks — the same CommonMark rule as [fencedBlock] (the delimiter must
/// be longer than any backtick run inside), just without the surrounding
/// newlines a block fence needs. For content that already contains no
/// backticks this is just a single pair, e.g. `` `text` ``.
String inlineCodeSpan(String text) {
  final fence = '`' * _delimiterLength(text, min: 1);
  return '$fence$text$fence';
}

/// The shortest run of backticks longer than any backtick run already inside
/// [text], no shorter than [min].
int _delimiterLength(String text, {required int min}) {
  final longest = RegExp('`+')
      .allMatches(text)
      .fold<int>(
        0,
        (max, m) => (m[0]?.length ?? 0) > max ? (m[0]?.length ?? 0) : max,
      );
  return longest < min ? min : longest + 1;
}
