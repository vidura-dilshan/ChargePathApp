import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// Singleton SQLite helper for storing favourite charging stations.
class FavoritesDb {
  static final FavoritesDb instance = FavoritesDb._init();
  static Database? _database;

  /// Notifier incremented on every add/remove — listeners auto-refresh.
  static final ValueNotifier<int> favoritesChanged = ValueNotifier(0);

  FavoritesDb._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('favorites.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE favorites (
        station_id               TEXT PRIMARY KEY,
        station_name             TEXT NOT NULL,
        address                  TEXT,
        charging_power           TEXT,
        available_plugs          TEXT,
        connector_slots          TEXT,
        supported_connector_types TEXT,
        latitude                 TEXT,
        longitude                TEXT,
        price_per_hour           TEXT
      )
    ''');
  }

  // ── PUBLIC API ─────────────────────────────────────────────────────────────

  Future<void> addFavorite(String stationId, Map<String, dynamic> data) async {
    final db = await database;
    await db.insert(
      'favorites',
      {
        'station_id': stationId,
        'station_name': data['station_name']?.toString() ?? '',
        'address': data['address']?.toString() ?? '',
        'charging_power': data['charging_power']?.toString() ?? '',
        'available_plugs': data['available_plugs']?.toString() ?? '',
        'connector_slots': data['connector_slots']?.toString() ?? '',
        'supported_connector_types':
            data['supported_connector_types']?.toString() ?? '',
        'latitude': data['latitude']?.toString() ?? '',
        'longitude': data['longitude']?.toString() ?? '',
        'price_per_hour': data['price_per_hour']?.toString() ?? '',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // Notify all listeners (e.g. HomePage) that favorites changed
    favoritesChanged.value++;
  }

  Future<void> removeFavorite(String stationId) async {
    final db = await database;
    await db.delete(
      'favorites',
      where: 'station_id = ?',
      whereArgs: [stationId],
    );
    // Notify all listeners (e.g. HomePage) that favorites changed
    favoritesChanged.value++;
  }

  Future<bool> isFavorite(String stationId) async {
    final db = await database;
    final rows = await db.query(
      'favorites',
      where: 'station_id = ?',
      whereArgs: [stationId],
    );
    return rows.isNotEmpty;
  }

  Future<List<Map<String, dynamic>>> getAllFavorites() async {
    final db = await database;
    return await db.query('favorites', orderBy: 'station_name ASC');
  }
}