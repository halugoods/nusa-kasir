import 'package:drift/drift.dart';

class Products extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get sku => text().nullable()();
  TextColumn get barcode => text().nullable()();
  TextColumn get category => text().withDefault(const Constant('Lainnya'))();
  IntColumn get buyPrice => integer().withDefault(const Constant(0))();
  IntColumn get sellPrice => integer()();
  IntColumn get stock => integer().withDefault(const Constant(0))();
  IntColumn get minStock => integer().withDefault(const Constant(0))();
  TextColumn get imagePath => text().nullable()();
  BoolColumn get isOnline => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
class StockMovements extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer()();
  TextColumn get type => text()();
  IntColumn get qty => integer()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
}
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get invoice => text()();
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
  TextColumn get items => text()();
  IntColumn get total => integer().withDefault(const Constant(0))();
  IntColumn get discount => integer().withDefault(const Constant(0))();
  TextColumn get paymentMethod => text().withDefault(const Constant('tunai'))();
  IntColumn get customerId => integer().nullable()();
  IntColumn get cashGiven => integer().nullable()();
  IntColumn get cashReturn => integer().nullable()();
  TextColumn get cashierName => text().nullable()();
  IntColumn get branchId => integer().nullable()();
  TextColumn get status => text().withDefault(const Constant('Normal'))();
  TextColumn get voidReason => text().nullable()();
  DateTimeColumn get voidedAt => dateTime().nullable()();
}
class Customers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  IntColumn get points => integer().withDefault(const Constant(0))();
  IntColumn get totalSpent => integer().withDefault(const Constant(0))();
  TextColumn get level => text().withDefault(const Constant('Silver'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
class Promos extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get code => text()();
  TextColumn get type => text()();
  IntColumn get value => integer()();
  IntColumn get minBelanja => integer().withDefault(const Constant(0))();
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get endDate => dateTime().nullable()();
  IntColumn get maxUses => integer().nullable()();
  IntColumn get usedCount => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('Aktif'))();
}
class Employees extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get pin => text()();
  TextColumn get role => text()();
  IntColumn get branchId => integer().nullable()();
  TextColumn get status => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
class Attendance extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get employeeId => integer()();
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
  TextColumn get checkIn => text().nullable()();
  TextColumn get checkOut => text().nullable()();
  IntColumn get pettyCash => integer().nullable()();
  IntColumn get finalCash => integer().nullable()();
}
class Expenses extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
  TextColumn get category => text()();
  TextColumn get description => text()();
  IntColumn get amount => integer()();
}
class Payroll extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get employeeId => integer()();
  TextColumn get period => text()();
  IntColumn get salary => integer()();
  IntColumn get bonus => integer().withDefault(const Constant(0))();
  IntColumn get deduction => integer().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
  TextColumn get status => text().withDefault(const Constant('Pending'))();
}
class Waste extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer()();
  IntColumn get qty => integer()();
  TextColumn get reason => text().nullable()();
  TextColumn get type => text().withDefault(const Constant('Expired'))();
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
}
class Liquidity extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
  TextColumn get type => text()();
  TextColumn get category => text()();
  TextColumn get description => text()();
  IntColumn get amount => integer()();
  TextColumn get method => text().nullable()();
}
class Suppliers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get contactPerson => text().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
class Branches extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
}
class Settings extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get storeName => text().withDefault(const Constant(''))();
  TextColumn get storeAddress => text().nullable()();
  TextColumn get storePhone => text().nullable()();
  TextColumn get posPrefix => text().nullable()();
  IntColumn get trxCounter => integer().withDefault(const Constant(0))();
  IntColumn get minStockAlert => integer().withDefault(const Constant(0))();
  TextColumn get qrisString => text().nullable()();
  TextColumn get themeMode => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}
class ActivationsLocal extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get key => text()();
  TextColumn get deviceId => text()();
  DateTimeColumn get activatedAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get status => text().withDefault(const Constant('active'))();
}
class SyncQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get taskType => text()();
  TextColumn get payload => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get errorMessage => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
class CashierSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get employeeId => integer()();
  DateTimeColumn get openedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get closedAt => dateTime().nullable()();
  IntColumn get startingCash => integer().withDefault(const Constant(0))();
  IntColumn get branchId => integer().nullable()();
}
class OnlineOrders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get invoice => text()();
  TextColumn get customerName => text()();
  TextColumn get customerPhone => text()();
  TextColumn get items => text()();  // JSON string
  IntColumn get subtotal => integer().withDefault(const Constant(0))();
  IntColumn get discount => integer().withDefault(const Constant(0))();
  IntColumn get handlingFee => integer().withDefault(const Constant(0))();
  IntColumn get total => integer()();
  TextColumn get paymentMethod => text().withDefault(const Constant('Tunai'))();
  TextColumn get pickupTime => text().nullable()();
  TextColumn get branch => text().withDefault(const Constant('Pusat'))();
  TextColumn get notes => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('Online Baru'))();
  TextColumn get processedBy => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
