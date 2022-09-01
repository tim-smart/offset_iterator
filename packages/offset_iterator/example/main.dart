// ignore_for_file: avoid_print

import 'package:offset_iterator/offset_iterator.dart';

/// A fake API representation
Future<String?> fetchPage(int page) async {
  await Future.delayed(const Duration(milliseconds: 50));
  if (page > 5) return null;
  return 'page $page content';
}

/// This iterator will continually pull pages from an API, until no more content
/// is left.
OffsetIterator<String> paginatedIterator() => OffsetIterator(
      // Start at page 1
      init: () => 1,
      process: (page) async {
        // Fetch the next page.
        final content = await fetchPage(page);

        // [OffsetIteratorState] lets the iterator know what to process next.
        return OffsetIteratorState(
          // Bump the page number
          acc: page + 1,
          // Return the page content in the chunk
          chunk: content != null ? [content] : [],
          // If content is null, then we have no more content left.
          hasMore: content != null,
        );
      },
    );

void main() async {
  final iterator = paginatedIterator();

  // `toList` is an extension method that consumes every item into a `List`.
  final pages = await iterator.toList();

  assert(pages ==
      [
        'page 1 content',
        'page 2 content',
        'page 3 content',
        'page 4 content',
        'page 5 content',
      ]);

  print(pages);
}
