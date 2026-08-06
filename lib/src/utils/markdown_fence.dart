/// Wraps [body] in a fence long enough to survive its own content.
///
/// A log message or response body can itself contain a ``` fence (LLM output,
/// CMS content, a pasted snippet). With a fixed 3-backtick fence that closes
/// the block early and leaks the payload into the rendered Markdown — and an
/// odd number of fences swallows every heading that follows. CommonMark says
/// the fence must be longer than any backtick run inside it, so measure first.
String fencedBlock(String body) {
  final text = body.trimRight();
  final longest = RegExp('`+')
      .allMatches(text)
      .fold<int>(
        0,
        (max, m) => (m[0]?.length ?? 0) > max ? (m[0]?.length ?? 0) : max,
      );
  final fence = '`' * (longest < 3 ? 3 : longest + 1);
  return '$fence\n$text\n$fence\n';
}
