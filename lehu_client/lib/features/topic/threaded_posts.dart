import '../../data/models/post.dart';

class ThreadedPost {
  const ThreadedPost({
    required this.post,
    required this.replies,
  });

  final Post post;
  final List<Post> replies;
}

List<ThreadedPost> buildThreadedPosts(List<Post> posts) {
  final byPostNumber = {
    for (final post in posts) post.postNumber: post,
  };
  final topLevelNumbers = <int>{};
  final repliesByParent = <int, List<Post>>{};

  for (final post in posts) {
    final parentNumber = _topLevelParentNumber(post, byPostNumber);
    if (parentNumber == null || parentNumber == post.postNumber) {
      topLevelNumbers.add(post.postNumber);
      continue;
    }
    repliesByParent.putIfAbsent(parentNumber, () => []).add(post);
  }

  return [
    for (final post in posts)
      if (topLevelNumbers.contains(post.postNumber))
        ThreadedPost(
          post: post,
          replies: List.unmodifiable(
            repliesByParent[post.postNumber] ?? const <Post>[],
          ),
        ),
  ];
}

int? _topLevelParentNumber(Post post, Map<int, Post> byPostNumber) {
  final replyTo = post.replyToPostNumber;
  if (replyTo == null) {
    return null;
  }

  var parent = byPostNumber[replyTo];
  if (parent == null) {
    return null;
  }

  final visited = <int>{post.postNumber};
  while (parent!.replyToPostNumber != null && visited.add(parent.postNumber)) {
    final next = byPostNumber[parent.replyToPostNumber];
    if (next == null) {
      break;
    }
    parent = next;
  }
  return parent.postNumber;
}
