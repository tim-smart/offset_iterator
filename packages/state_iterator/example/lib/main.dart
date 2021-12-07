import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:offset_iterator_riverpod/offset_iterator_riverpod.dart';

/// Creates a new [StateIterator] for our counter state.
StateIterator<int> counterIterator() => StateIterator(
      name: 'counterIterator',
      initialState: 0,
    );

/// Define a helper type for our counter actions
typedef CounterAction = StateIteratorAction<int>;

// Some actions for our counter
CounterAction increment() => (count, add) => add(count + 1);
CounterAction decrement() => (count, add) => add(count - 1);
CounterAction reset() => (count, add) => add(0);

/// Riverpod provider for our [StateIterator].
final counterIteratorProvider =
    Provider((ref) => stateIteratorProvider<int>(ref)(counterIterator()));

/// Riverpod provider for exposing the [counterIterator] value.
final counterProvider = Provider((ref) =>
    stateIteratorValueProvider<int>(ref)(ref.watch(counterIteratorProvider)));

// === Flutter app below

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
        home: const MyHomePage(title: 'StateIterator demo'),
      ),
    );
  }
}

class MyHomePage extends ConsumerWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Using riverpod to use the counter iterator.
    final counter = ref.watch(counterIteratorProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('You have pushed the button this many times:'),

            //
            CounterText(style: Theme.of(context).textTheme.headline4),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Some buttons that dispatch actions to the [counterIterator].
          FloatingActionButton(
            onPressed: () => counter.add(increment()),
            tooltip: 'Increment',
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            onPressed: () => counter.add(decrement()),
            tooltip: 'Decrement',
            child: const Icon(Icons.remove),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            onPressed: () => counter.add(reset()),
            tooltip: 'Reset',
            child: const Icon(Icons.restore),
          ),
        ],
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}

/// Example of a widget that consumes the counter value using riverpod's
/// [ConsumerWidget].
class CounterText extends ConsumerWidget {
  const CounterText({Key? key, this.style}) : super(key: key);

  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(counterProvider);
    return Text('$count', style: style);
  }
}
