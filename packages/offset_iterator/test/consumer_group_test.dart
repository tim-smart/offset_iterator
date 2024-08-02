import 'package:offset_iterator/offset_iterator.dart';
import 'package:test/test.dart';

void main() {
  group('offset tracking', () {
    test('ensures children do not miss items', () async {
      final parent = OffsetIterator.range(0, end: 5, retention: -1);
      final g = parent.consumerGroup();
      final child1 = g.consumer();
      final child2 = g.consumer();

      expect(parent.earliestAvailableOffset, 0);
      expect(await child1.pull(), equals(const Option.of(0)));
      await Future.microtask(() {});
      expect(parent.earliestAvailableOffset, 1);

      expect(await child1.pull(), equals(const Option.of(1)));
      await Future.microtask(() {});
      expect(parent.earliestAvailableOffset, 1);

      expect(await child2.pull(), equals(const Option.of(0)));
      await Future.microtask(() {});
      expect(parent.earliestAvailableOffset, 2);

      expect(await child2.pull(), equals(const Option.of(1)));
      await Future.microtask(() {});
      expect(parent.earliestAvailableOffset, 2);
      expect(parent.log.isEmpty, true);

      expect(await child1.toList(), [2, 3, 4, 5]);
      await Future.microtask(() {});
      expect(parent.earliestAvailableOffset, 3);
      expect(parent.log.toList(),
          [const Option.of(2), const Option.of(3), const Option.of(4)]);

      expect(await child2.pull(), equals(const Option.of(2)));
      await Future.microtask(() {});
      expect(parent.earliestAvailableOffset, 4);

      expect(await child2.toList(), [3, 4, 5]);
      await Future.microtask(() {});
      expect(parent.earliestAvailableOffset, 6);

      expect(parent.log.isEmpty, true);
      expect(parent.status, OffsetIteratorStatus.completed);
      expect(child1.status, OffsetIteratorStatus.completed);
      expect(child2.status, OffsetIteratorStatus.completed);
    });
  });

  group('seed', () {
    test('is propogated', () async {
      final parent = OffsetIterator.range(
        0,
        end: 5,
        retention: -1,
        seed: () => const Option.of(-1),
      );
      final g = parent.consumerGroup();
      final child = g.consumer();

      expect(child.value, const Option.of(-1));

      expect(parent.status, OffsetIteratorStatus.seeded);
      expect(child.status, OffsetIteratorStatus.seeded);
    });
  });

  group('.children', () {
    test('keeps track of registration', () async {
      final g = OffsetIterator.range(0, end: 5, retention: -1).consumerGroup();

      final child1 = g.consumer();
      expect(g.children, equals({child1}));

      final child2 = g.consumer();
      expect(g.children, equals({child1, child2}));

      g.deregister(child1);
      expect(g.children, equals({child2}));
    });
  });
}
