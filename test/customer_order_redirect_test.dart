import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:city_store/services/navigation.dart';

void main() {
  testWidgets(
    'successful order opens My Orders even when checkout began on entry cards',
    (tester) async {
      shellTab.value = 0;
      final initialRequest = enterShellRequest.value;
      addTearDown(() {
        shellTab.value = 0;
        enterShellRequest.value = initialRequest;
      });

      await tester.pumpWidget(const MaterialApp(home: _EntryHarness()));
      await tester.tap(find.text('Browse stores'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Checkout'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm success'), findsOneWidget);

      await tester.tap(find.text('Confirm success'));
      await tester.pumpAndSettle();

      expect(shellTab.value, 2);
      expect(enterShellRequest.value, initialRequest + 1);
      expect(find.text('My Orders'), findsOneWidget);
      expect(find.text('Confirm success'), findsNothing);
      expect(find.text('Browse stores'), findsNothing);
    },
  );
}

/// Mirrors the entry screen's enterShellRequest listener without Firebase.
class _EntryHarness extends StatefulWidget {
  const _EntryHarness();

  @override
  State<_EntryHarness> createState() => _EntryHarnessState();
}

class _EntryHarnessState extends State<_EntryHarness> {
  bool _entered = false;

  @override
  void initState() {
    super.initState();
    enterShellRequest.addListener(_enterShell);
  }

  void _enterShell() => setState(() => _entered = true);

  @override
  void dispose() {
    enterShellRequest.removeListener(_enterShell);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_entered) {
      return const Scaffold(body: Center(child: Text('My Orders')));
    }
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const _StoreHarness()),
          ),
          child: const Text('Browse stores'),
        ),
      ),
    );
  }
}

class _StoreHarness extends StatelessWidget {
  const _StoreHarness();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const _CheckoutHarness()),
            ),
            child: const Text('Checkout'),
          ),
        ),
      );
}

class _CheckoutHarness extends StatelessWidget {
  const _CheckoutHarness();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => openCustomerTab(context, 2),
            child: const Text('Confirm success'),
          ),
        ),
      );
}
