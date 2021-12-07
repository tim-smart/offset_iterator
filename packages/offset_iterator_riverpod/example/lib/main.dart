import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:offset_iterator_riverpod/offset_iterator_riverpod.dart';

/// Type alias to make code easier to read
typedef Post = Map<String, dynamic>;

/// Function that fetches a page of posts
Future<List<Post>> fetchPosts(int page) =>
    Dio().get('https://jsonplaceholder.typicode.com/posts', queryParameters: {
      '_limit': '15',
      '_page': '$page',
    }).then((r) => List<Post>.from(r.data));

/// [OffsetIterator] of posts
OffsetIterator<List<Post>> postsIterator() => OffsetIterator(
      init: () => 1,
      process: (page) async {
        print('Fetching page $page...');
        final posts = await fetchPosts(page);
        return OffsetIteratorState(
          acc: page + 1,
          chunk: [posts],
          hasMore: posts.isNotEmpty,
        );
      },
    )
        // Accumlate adds the pages together into one long list
        .accumulate()
        // Prefetch will fetch one more page than we actually need, to make loading the list fast.
        .prefetch();

/// A [Provider] that uses [iteratorValueProvider] to expose an
/// [OffsetIteratorAsyncValue] for our [postsIterator].
final postsProvider = Provider.autoDispose(
    (ref) => iteratorValueProvider<List<Post>>(ref)(postsIterator()));

/// A wrapper widget that uses the value from [postsProvider].
/// It handles the data / error / loading states.
class PostsListContainer extends ConsumerWidget {
  const PostsListContainer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(postsProvider);

    return state.value.when(
      data: (posts) => PostsList(
        posts: posts,
        hasMore: state.hasMore,
        loadMore: state.pull,
      ),
      error: (err, stack) => Center(child: Text('Error: $err')),
      loading: () => const Center(child: Text('Loading...')),
    );
  }
}

/// The list of posts using [ListView.builder].
class PostsList extends StatelessWidget {
  PostsList({
    Key? key,
    required this.posts,
    required this.hasMore,
    required this.loadMore,
  }) : super(key: key);

  final List<Post> posts;
  final bool hasMore;
  final void Function() loadMore;

  late final postsLength = posts.length;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemBuilder: (context, index) {
        final post = posts[index];

        // At the end of the list load more posts
        if (hasMore && index == postsLength - 1) {
          loadMore();
        }

        return ListTile(
          title: Text(post['title']),
          subtitle: Text(post['body']),
        );
      },
      itemCount: postsLength,
    );
  }
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp(
        title: 'Flutter Demo',
        theme: ThemeData(
          primarySwatch: Colors.blue,
        ),
        home: const MyHomePage(title: 'offset_iterator_riverpod'),
      ),
    );
  }
}

class MyHomePage extends StatelessWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: const PostsListContainer(),
    );
  }
}
