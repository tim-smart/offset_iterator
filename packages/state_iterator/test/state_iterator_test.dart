import 'package:fpdart/fpdart.dart';
import 'package:state_iterator/state_iterator.dart';
import 'package:test/test.dart';

typedef CounterAction = StateIteratorAction<int>;
CounterAction increment() => (count, add) => add(count + 1);
CounterAction decrement() => (count, add) => add(count - 1);

void main() {
  group('basic', () {
    test('it works', () async {
      final i = StateIterator(initialState: 0);

      expect(i.iterator.value, some(0));

      i.add(increment());
      i.add(increment());
      i.add(decrement());
      i.close();

      expect(await i.iterator.toList(), [1, 2, 1]);
    });
  });
}
