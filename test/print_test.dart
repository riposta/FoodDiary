import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_diary/pdf_report.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<String> mockPrinting({required bool hasPrintService}) {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('net.nfet.printing'), (call) async {
      calls.add(call.method);
      if (call.method == 'printPdf' && !hasPrintService) {
        // to, co Android zwraca bez usługi druku (np. BlueStacks)
        throw PlatformException(code: 'error', message: 'No Activity found to handle null');
      }
      return 1;
    });
    return calls;
  }

  test('brak usługi druku -> udostępnianie PDF zamiast błędu', () async {
    final calls = mockPrinting(hasPrintService: false);
    final printed = await printOrShare(Uint8List.fromList([1, 2, 3]), 'dzienniczek.pdf');
    expect(printed, isFalse);
    expect(calls, containsAllInOrder(['printPdf', 'sharePdf']));
  });
}
