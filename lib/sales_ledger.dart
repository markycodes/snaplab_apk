import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum SalePaymentMethod { coin, qrPh }

class SalesLedger {
  SalesLedger({
    SharedPreferencesAsync? preferences,
    Future<String?> Function()? readStorage,
    Future<void> Function(String value)? writeStorage,
  }) : _preferences = preferences,
       _readStorage = readStorage,
       _writeStorage = writeStorage {
    if ((readStorage == null) != (writeStorage == null)) {
      throw ArgumentError(
        'Provide both sales storage callbacks or neither of them.',
      );
    }
    if (readStorage == null && preferences == null) {
      _preferences = SharedPreferencesAsync();
    }
  }

  static const _storageKey = 'sales_ledger_v1';
  SharedPreferencesAsync? _preferences;
  final Future<String?> Function()? _readStorage;
  final Future<void> Function(String value)? _writeStorage;

  Future<Map<String, Object?>> load({DateTime? now}) async {
    final referenceDate = now ?? DateTime.now();
    final stored = await _read();
    return _summary(stored, referenceDate);
  }

  Future<Map<String, Object?>> reset({DateTime? now}) async {
    final stored = <String, Object?>{
      'totalSales': 0,
      'totalTransactions': 0,
      'totalCoinSales': 0,
      'totalCoinTransactions': 0,
      'totalQrPhSales': 0,
      'totalQrPhTransactions': 0,
      'days': <String, _DailySales>{},
    };
    final encoded = _encode(stored);
    final writeStorage = _writeStorage;
    if (writeStorage != null) {
      await writeStorage(encoded);
    } else {
      await _preferences!.setString(_storageKey, encoded);
    }
    return _summary(stored, now ?? DateTime.now());
  }

  Future<Map<String, Object?>> recordSale({
    required int amount,
    required int photoCount,
    required SalePaymentMethod paymentMethod,
    DateTime? at,
  }) async {
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'Must be greater than zero.');
    }
    if (photoCount < 1 || photoCount > 5) {
      throw ArgumentError.value(
        photoCount,
        'photoCount',
        'Must be between 1 and 5.',
      );
    }

    final saleTime = at ?? DateTime.now();
    final today = _dateKey(saleTime);
    final stored = await _read();
    final days = stored['days'] as Map<String, _DailySales>;
    final daily = days.putIfAbsent(today, _DailySales.new);
    daily.sales += amount;
    daily.transactions++;
    daily.photos += photoCount;
    stored['totalSales'] = (stored['totalSales'] as int) + amount;
    stored['totalTransactions'] = (stored['totalTransactions'] as int) + 1;
    if (paymentMethod == SalePaymentMethod.coin) {
      daily.coinSales += amount;
      daily.coinTransactions++;
      stored['totalCoinSales'] = (stored['totalCoinSales'] as int) + amount;
      stored['totalCoinTransactions'] =
          (stored['totalCoinTransactions'] as int) + 1;
    } else {
      daily.qrPhSales += amount;
      daily.qrPhTransactions++;
      stored['totalQrPhSales'] = (stored['totalQrPhSales'] as int) + amount;
      stored['totalQrPhTransactions'] =
          (stored['totalQrPhTransactions'] as int) + 1;
    }

    final firstDay = DateTime(saleTime.year, saleTime.month, saleTime.day - 6);
    days.removeWhere((date, _) {
      final parsed = DateTime.tryParse(date);
      return parsed == null || parsed.isBefore(firstDay);
    });
    final encoded = _encode(stored);
    final writeStorage = _writeStorage;
    if (writeStorage != null) {
      await writeStorage(encoded);
    } else {
      await _preferences!.setString(_storageKey, encoded);
    }
    return _summary(stored, saleTime);
  }

  Future<Map<String, Object?>> _read() async {
    final readStorage = _readStorage;
    final encoded = readStorage != null
        ? await readStorage()
        : await _preferences!.getString(_storageKey);
    if (encoded == null) {
      return {
        'totalSales': 0,
        'totalTransactions': 0,
        'totalCoinSales': 0,
        'totalCoinTransactions': 0,
        'totalQrPhSales': 0,
        'totalQrPhTransactions': 0,
        'days': <String, _DailySales>{},
      };
    }

    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('The saved sales ledger is invalid.');
    }
    final totalSales = decoded['totalSales'];
    final totalTransactions = decoded['totalTransactions'];
    final totalCoinSales = decoded['totalCoinSales'] ?? 0;
    final totalCoinTransactions = decoded['totalCoinTransactions'] ?? 0;
    final totalQrPhSales = decoded['totalQrPhSales'] ?? 0;
    final totalQrPhTransactions = decoded['totalQrPhTransactions'] ?? 0;
    final rawDays = decoded['days'];
    if (totalSales is! int ||
        totalSales < 0 ||
        totalTransactions is! int ||
        totalTransactions < 0 ||
        totalCoinSales is! int ||
        totalCoinSales < 0 ||
        totalCoinTransactions is! int ||
        totalCoinTransactions < 0 ||
        totalQrPhSales is! int ||
        totalQrPhSales < 0 ||
        totalQrPhTransactions is! int ||
        totalQrPhTransactions < 0 ||
        rawDays is! Map<String, dynamic>) {
      throw const FormatException('The saved sales ledger is invalid.');
    }

    final days = <String, _DailySales>{};
    for (final entry in rawDays.entries) {
      final date = DateTime.tryParse(entry.key);
      final rawDaily = entry.value;
      if (date == null ||
          _dateKey(date) != entry.key ||
          rawDaily is! Map<String, dynamic> ||
          rawDaily['sales'] is! int ||
          rawDaily['sales'] < 0 ||
          rawDaily['transactions'] is! int ||
          rawDaily['transactions'] < 0 ||
          rawDaily['photos'] is! int ||
          rawDaily['photos'] < 0 ||
          (rawDaily['coinSales'] ?? 0) is! int ||
          (rawDaily['coinSales'] ?? 0) < 0 ||
          (rawDaily['coinTransactions'] ?? 0) is! int ||
          (rawDaily['coinTransactions'] ?? 0) < 0 ||
          (rawDaily['qrPhSales'] ?? 0) is! int ||
          (rawDaily['qrPhSales'] ?? 0) < 0 ||
          (rawDaily['qrPhTransactions'] ?? 0) is! int ||
          (rawDaily['qrPhTransactions'] ?? 0) < 0) {
        throw const FormatException('The saved sales ledger is invalid.');
      }
      days[entry.key] = _DailySales(
        sales: rawDaily['sales'] as int,
        transactions: rawDaily['transactions'] as int,
        photos: rawDaily['photos'] as int,
        coinSales: (rawDaily['coinSales'] ?? 0) as int,
        coinTransactions: (rawDaily['coinTransactions'] ?? 0) as int,
        qrPhSales: (rawDaily['qrPhSales'] ?? 0) as int,
        qrPhTransactions: (rawDaily['qrPhTransactions'] ?? 0) as int,
      );
    }
    return {
      'totalSales': totalSales,
      'totalTransactions': totalTransactions,
      'totalCoinSales': totalCoinSales,
      'totalCoinTransactions': totalCoinTransactions,
      'totalQrPhSales': totalQrPhSales,
      'totalQrPhTransactions': totalQrPhTransactions,
      'days': days,
    };
  }

  Map<String, Object?> _summary(
    Map<String, Object?> stored,
    DateTime referenceDate,
  ) {
    final today = _dateKey(referenceDate);
    final days = stored['days'] as Map<String, _DailySales>;
    final todaySales = days[today];
    final week = List<Map<String, Object?>>.generate(7, (index) {
      final date = DateTime(
        referenceDate.year,
        referenceDate.month,
        referenceDate.day - 6 + index,
      );
      final dateKey = _dateKey(date);
      final daily = days[dateKey];
      return {
        'date': dateKey,
        'sales': daily?.sales ?? 0,
        'transactions': daily?.transactions ?? 0,
        'photos': daily?.photos ?? 0,
        'coinSales': daily?.coinSales ?? 0,
        'coinTransactions': daily?.coinTransactions ?? 0,
        'qrPhSales': daily?.qrPhSales ?? 0,
        'qrPhTransactions': daily?.qrPhTransactions ?? 0,
      };
    });
    return {
      'totalSales': stored['totalSales'],
      'totalTransactions': stored['totalTransactions'],
      'totalCoinSales': stored['totalCoinSales'],
      'totalCoinTransactions': stored['totalCoinTransactions'],
      'totalQrPhSales': stored['totalQrPhSales'],
      'totalQrPhTransactions': stored['totalQrPhTransactions'],
      'salesToday': todaySales?.sales ?? 0,
      'transactionsToday': todaySales?.transactions ?? 0,
      'coinSalesToday': todaySales?.coinSales ?? 0,
      'coinTransactionsToday': todaySales?.coinTransactions ?? 0,
      'qrPhSalesToday': todaySales?.qrPhSales ?? 0,
      'qrPhTransactionsToday': todaySales?.qrPhTransactions ?? 0,
      'salesThisWeek': week.fold<int>(
        0,
        (total, day) => total + (day['sales'] as int),
      ),
      'coinSalesThisWeek': week.fold<int>(
        0,
        (total, day) => total + (day['coinSales'] as int),
      ),
      'qrPhSalesThisWeek': week.fold<int>(
        0,
        (total, day) => total + (day['qrPhSales'] as int),
      ),
      'week': week,
    };
  }

  String _encode(Map<String, Object?> stored) {
    final days = stored['days'] as Map<String, _DailySales>;
    return jsonEncode({
      'totalSales': stored['totalSales'],
      'totalTransactions': stored['totalTransactions'],
      'totalCoinSales': stored['totalCoinSales'],
      'totalCoinTransactions': stored['totalCoinTransactions'],
      'totalQrPhSales': stored['totalQrPhSales'],
      'totalQrPhTransactions': stored['totalQrPhTransactions'],
      'days': {
        for (final entry in days.entries)
          entry.key: {
            'sales': entry.value.sales,
            'transactions': entry.value.transactions,
            'photos': entry.value.photos,
            'coinSales': entry.value.coinSales,
            'coinTransactions': entry.value.coinTransactions,
            'qrPhSales': entry.value.qrPhSales,
            'qrPhTransactions': entry.value.qrPhTransactions,
          },
      },
    });
  }

  String _dateKey(DateTime date) {
    final localDate = date.toLocal();
    final year = localDate.year.toString().padLeft(4, '0');
    final month = localDate.month.toString().padLeft(2, '0');
    final day = localDate.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}

class _DailySales {
  _DailySales({
    this.sales = 0,
    this.transactions = 0,
    this.photos = 0,
    this.coinSales = 0,
    this.coinTransactions = 0,
    this.qrPhSales = 0,
    this.qrPhTransactions = 0,
  });

  int sales;
  int transactions;
  int photos;
  int coinSales;
  int coinTransactions;
  int qrPhSales;
  int qrPhTransactions;
}
