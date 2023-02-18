import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:offset_iterator_riverpod/offset_iterator_riverpod.dart';

/// Type alias to make code easier to read
typedef Post = Map<String, dynamic>;

/// Function that fetches a page of posts
Future<List<Post>> fetchPosts(int page, int limit) =>
    Dio().get('https://jsonplaceholder.typicode.com/posts', queryParameters: {
      '_limit': '$limit',
      '_page': '$page',
    }).then((r) => List<Post>.from(r.data));

/// [OffsetIterator] of posts
OffsetIterator<List<Post>> postsIterator() => OffsetIterator(
      init: () => 1,
      process: (page) async {
        // ignore: avoid_print
        print('Fetching page $page...');
        final posts = await fetchPosts(page, 30);
        return OffsetIteratorState(
          acc: page + 1, // Increment the page number
          chunk: [posts], // Emit the list of posts
          hasMore: posts.length == 30, // Stop if we only receive a partial page
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
    (AutoDisposeProviderRef<OffsetIteratorAsyncValue<List<Post>>> ref) =>
        iteratorValueProvider<List<Post>>(ref)(postsIterator()));

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
      error: (err, stack) => SliverFillRemaining(
        child: Center(child: Text('Error: $err')),
      ),
      loading: () => const SliverFillRemaining(
        child: Center(child: Text('Loading...')),
      ),
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
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
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
        childCount: postsLength,
      ),
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

class MyHomePage extends ConsumerWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => ref.refresh(postsProvider),
        child: const Icon(Icons.refresh),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: Text(title),
            floating: true,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(
                bottom: 5,
                left: 16,
                top: 25,
              ),
              child: Text('Posts:', style: theme.textTheme.headlineSmall!),
            ),
          ),
          const PostsListContainer(),
          const SliverToBoxAdapter(child: SizedBox(height: 30)),
        ],
      ),
    );
  }
}
