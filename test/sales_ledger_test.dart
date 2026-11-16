import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth_kiosk/sales_ledger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SalesLedger ledger;
  String? savedLedger;

  setUp(() {
    savedLedger = null;
    ledger = SalesLedger(
      readStorage: () async => savedLedger,
      writeStorage: (value) async => savedLedger = value,
    );
  });

  test('persists lifetime sales and provides a seven-day breakdown', () async {
    final today = DateTime(2026, 10, 16, 12);
    await ledger.recordSale(
      amount: 8,
      photoCount: 2,
      paymentMethod: SalePaymentMethod.coin,
      at: today,
    );
    await ledger.recordSale(
      amount: 4,
      photoCount: 1,
      paymentMethod: SalePaymentMethod.qrPh,
      at: today.subtract(const Duration(days: 2)),
    );

    final summary = await ledger.load(now: today);
    expect(summary['totalSales'], 12);
    expect(summary['totalTransactions'], 2);
    expect(summary['totalCoinSales'], 8);
    expect(summary['totalQrPhSales'], 4);
    expect(summary['salesToday'], 8);
    expect(summary['transactionsToday'], 1);
    expect(summary['coinSalesToday'], 8);
    expect(summary['qrPhSalesToday'], 0);
    expect(summary['salesThisWeek'], 12);
    expect(summary['coinSalesThisWeek'], 8);
    expect(summary['qrPhSalesThisWeek'], 4);
    expect(
      (summary['week'] as List<Map<String, Object?>>)
          .map((day) => day['sales'])
          .toList(),
      [0, 0, 0, 0, 4, 0, 8],
    );
    expect(
      (summary['week'] as List<Map<String, Object?>>)
          .map((day) => day['coinSales'])
          .toList(),
      [0, 0, 0, 0, 0, 0, 8],
    );
    expect(
      (summary['week'] as List<Map<String, Object?>>)
          .map((day) => day['qrPhSales'])
          .toList(),
      [0, 0, 0, 0, 4, 0, 0],
    );
  });

  test('reset clears lifetime totals and daily sales history', () async {
    final today = DateTime(2026, 10, 16, 12);
    await ledger.recordSale(
      amount: 20,
      photoCount: 3,
      paymentMethod: SalePaymentMethod.qrPh,
      at: today,
    );

    final resetSummary = await ledger.reset(now: today);
    expect(resetSummary['totalSales'], 0);
    expect(resetSummary['totalTransactions'], 0);
    expect(resetSummary['totalCoinSales'], 0);
    expect(resetSummary['totalQrPhSales'], 0);
    expect(resetSummary['salesToday'], 0);
    expect(resetSummary['transactionsToday'], 0);
    expect(
      (resetSummary['week'] as List<Map<String, Object?>>).every(
        (day) => day['sales'] == 0,
      ),
      isTrue,
    );
    expect((await ledger.load(now: today))['totalSales'], 0);
  });

  test(
    'keeps all-time totals but removes daily entries outside the week',
    () async {
      final today = DateTime(2026, 10, 16, 12);
      await ledger.recordSale(
        amount: 10,
        photoCount: 2,
        paymentMethod: SalePaymentMethod.coin,
        at: today.subtract(const Duration(days: 8)),
      );
      await ledger.recordSale(
        amount: 3,
        photoCount: 1,
        paymentMethod: SalePaymentMethod.qrPh,
        at: today,
      );

      final summary = await ledger.load(now: today);
      expect(summary['totalSales'], 13);
      expect(summary['totalCoinSales'], 10);
      expect(summary['totalQrPhSales'], 3);
      expect(summary['salesThisWeek'], 3);
      expect(summary['coinSalesThisWeek'], 0);
      expect(summary['qrPhSalesThisWeek'], 3);
    },
  );

  test(
    'accepts five-photo sales and rejects invalid amounts or counts',
    () async {
      final summary = await ledger.recordSale(
        amount: 20,
        photoCount: 5,
        paymentMethod: SalePaymentMethod.coin,
      );
      expect(summary['totalTransactions'], 1);
      expect(summary['totalCoinSales'], 20);
      expect(summary['totalQrPhSales'], 0);
      await expectLater(
        ledger.recordSale(
          amount: 0,
          photoCount: 1,
          paymentMethod: SalePaymentMethod.coin,
        ),
        throwsArgumentError,
      );
      await expectLater(
        ledger.recordSale(
          amount: 1,
          photoCount: 6,
          paymentMethod: SalePaymentMethod.qrPh,
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'loads older combined-only ledgers without losing total sales',
    () async {
      savedLedger =
          '{"totalSales":32,"totalTransactions":2,'
          '"days":{"2026-10-16":{"sales":32,"transactions":2,"photos":3}}}';

      final summary = await ledger.load(now: DateTime(2026, 10, 16));

      expect(summary['totalSales'], 32);
      expect(summary['totalCoinSales'], 0);
      expect(summary['totalQrPhSales'], 0);
      expect(summary['salesToday'], 32);
      expect(summary['coinSalesToday'], 0);
      expect(summary['qrPhSalesToday'], 0);
    },
  );
}
