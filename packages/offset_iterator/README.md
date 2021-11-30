# offset_iterator

`OffsetIterator` is an offset-based async iterable for true pull-based data
streaming. Inspired by Apache Kafka.

Great for:

- IO based streaming
- Paginated API calls

## Example

Here is an example straight from the tests, that fetches up to 5 pages from a fake API.
[You can view the test case here.](https://github.com/tim-smart/offset_iterator/blob/main/packages/offset_iterator/test/offset_iterator_test.dart#L11)

Note that it will only call `fetchPage` once, as we only request one page.

```dart
Future<String> fetchPage(int page) async {
  print('Fetching page $page!');
  await Future.delayed(const Duration(milliseconds: 50));
  return 'page content $page';
}

final i = OffsetIterator(
  init: () => 1, // Start from page 1
  process: (nextPage) async {
    final pageContent = await fetchPage(nextPage);
    return OffsetIteratorState(
      acc: nextPage + 1, // Set the next accumulator / cursor
      chunk: [pageContent], // Add the page content
      hasMore: nextPage < 5, // We only want 5 pages
    );
  },
);

final firstPage = await i.pull();
print(firstPage.toNullable());

// In the logs:
// "Fetching page 1!"
// "page content 1"
```

## Usage with Flutter

A
[`offset_iterator_builder`](https://github.com/tim-smart/offset_iterator/tree/main/packages/offset_iterator_builder)
package is available.

This package can be used to build widgets from an `OffsetIterator`'s value. The
`builder` function is given the current `BuildContext`, the latest value from
the iterator and a `pull` function for requesting more data.

The builder provides a `withValue` helper function to make using the state easier!

```dart
class MyList extends StatelessWidget {
    MyList({Key? key, required this.iterator}) : super(key: key);

    final OffsetIterator<List<int>> iterator;

    @override
    Widget build(BuildContext context) => OffsetIteratorBuilder(
        iterator: iterator,
        builder: (context, value, pull) => withValue(value)(
            data: (listOfNumbers, hasMore) => Text('I have ${listOfNumbers.length} numbers!'),
            loading: () => Text('Loading...'),
            error: (err) => Text('Error: $err'),
        ),
    );
}
```
