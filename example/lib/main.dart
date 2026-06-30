import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'objectbox.g.dart';
import 'objectbox_browser_source.dart';
import 'objectbox_entities.dart';
import 'sqflite_browser_source.dart';

// Enable the live system notification summarising network calls (opt-in).
// On Android this requires a notification icon + (Android 13+) the
// POST_NOTIFICATIONS permission; on iOS/macOS the user is prompted on init.
late final FlutterInspector inspector;
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  inspector = FlutterInspector(
    showNetworkNotification: true,
    navigatorKey: navigatorKey,
    // Capture uncaught errors into the Console as LogLevel.error logs (opt-in).
    // This wires the three standard hooks — FlutterError.onError,
    // PlatformDispatcher.instance.onError and ErrorWidget.builder — which
    // together cover framework, asynchronous and build-time errors. No zone is
    // involved, so there is no Zone mismatch to worry about.
    captureUncaughtErrors: true,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Flutter Inspector Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      navigatorObservers: [inspector.navigatorObserver],
      builder: (context, child) {
        return FlutterInspectorMagicalTap(
          onTap: () {
            final context = navigatorKey.currentContext;

            if (context == null) return;

            inspector.openDashboard(context);
          },
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const MyHomePage(title: 'Flutter Inspector Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;
  late final Dio _dio;

  @override
  void initState() {
    super.initState();
    _dio = Dio();
    // Pass `sourceDio: _dio` so each captured entry remembers the Dio that
    // issued it, enabling the Resend action in the network detail view to
    // replay the request through the original Dio.
    _dio.interceptors.add(
      FlutterInspectorDioInterceptor(inspector, sourceDio: _dio),
    );

    // Show FAB after frame builds
    WidgetsBinding.instance.addPostFrameCallback((_) {
      inspector.attach(context: context);
    });
  }

  @override
  void dispose() {
    _sqliteDb?.close();
    _objectboxStore?.close();
    super.dispose();
  }

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
    inspector.log('Counter incremented to $_counter', level: LogLevel.info);
    inspector.database(
      DatabaseOperation.update,
      'counters',
      affectedRows: 1,
      data: {'query': 'UPDATE counters SET val = $_counter'},
    );
  }

  Future<void> _makeNetworkRequest() async {
    try {
      final Options option = Options(
        headers: {
          "Authorization": "Bearer mock-token-123",
          "Set-Cookie": "mock-cookie-123",
          "X-Api-Key": "mock-api-key-123",
        },
      );
      await _dio.get(
        'https://jsonplaceholder.typicode.com/todos/1',
        options: option,
      );
      inspector.log('Network request successful', level: LogLevel.info);
    } catch (e) {
      inspector.log('Network request failed: $e', level: LogLevel.error);
    }
  }

  bool _sqliteRegistered = false;
  Database? _sqliteDb;
  bool _objectboxRegistered = false;
  Store? _objectboxStore;

  Future<void> _seedSqlite() async {
    if (_sqliteRegistered) return;
    try {
      final databasesPath = await getDatabasesPath();
      final path = '$databasesPath/demo.db';

      // version 2 added the `member` table. Both onCreate (fresh install) and
      // onUpgrade (existing demo.db from v1, which only had `users`) build the
      // tables via the same IF NOT EXISTS statements, so a device with an old
      // single-table db still gets `member` instead of failing on query.
      _sqliteDb = await openDatabase(
        path,
        version: 2,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, name TEXT, email TEXT, age INTEGER)',
          );
          await db.execute(
            'CREATE TABLE IF NOT EXISTS member (id INTEGER PRIMARY KEY, name TEXT, email TEXT, age INTEGER)',
          );
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              'CREATE TABLE IF NOT EXISTS member (id INTEGER PRIMARY KEY, name TEXT, email TEXT, age INTEGER)',
            );
          }
        },
      );

      final usersResult = await _sqliteDb?.rawQuery(
        'SELECT COUNT(*) as count FROM users',
      );
      final usersCount = Sqflite.firstIntValue(usersResult ?? []) ?? 0;
      if (usersCount == 0) {
        await _sqliteDb?.insert('users', {
          'id': 1,
          'name': 'Alice',
          'email': 'alice@example.com',
          'age': 30,
        });
        await _sqliteDb?.insert('users', {
          'id': 2,
          'name': 'Bob',
          'email': null,
          'age': 25,
        });
        await _sqliteDb?.insert('users', {
          'id': 3,
          'name': 'Carol',
          'email': 'carol@example.com',
          'age': null,
        });
      }

      final membersResult = await _sqliteDb?.rawQuery(
        'SELECT COUNT(*) as count FROM member',
      );
      final membersCount = Sqflite.firstIntValue(membersResult ?? []) ?? 0;
      if (membersCount == 0) {
        await _sqliteDb?.insert('member', {
          'id': 1,
          'name': 'Alice',
          'email': 'alice@example.com',
          'age': 30,
        });
        await _sqliteDb?.insert('member', {
          'id': 2,
          'name': 'Bob',
          'email': null,
          'age': 25,
        });
        await _sqliteDb?.insert('member', {
          'id': 3,
          'name': 'Carol',
          'email': 'carol@example.com',
          'age': null,
        });
      }

      if (!_sqliteRegistered && _sqliteDb != null) {
        inspector.registerDatabaseSource(
          SqfliteBrowserSource(_sqliteDb!, name: 'demo.db'),
        );
        _sqliteRegistered = true;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SQLite demo.db initialized and registered!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('SQLite seeding failed: $e')));
      }
    }
  }

  Future<void> _seedObjectBox() async {
    // ObjectBox relies on native libraries and does NOT support web.
    // Fail loudly-but-gracefully instead of crashing the app.
    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'ObjectBox is not supported on web. '
              'Run this demo on a mobile or desktop target.',
            ),
          ),
        );
      }
      return;
    }
    if (_objectboxRegistered) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final store = await openStore(directory: '${dir.path}/objectbox-demo');
      _objectboxStore = store;

      final noteBox = store.box<Note>();
      if (noteBox.isEmpty()) {
        noteBox.putMany([
          Note(title: 'Welcome', body: 'This row comes from ObjectBox.'),
          Note(title: 'No SQL here', body: null),
          Note(title: 'Strongly typed', body: 'Mapped by hand in the source.'),
        ]);
      }

      final tagBox = store.box<Tag>();
      if (tagBox.isEmpty()) {
        tagBox.putMany([Tag(label: 'demo'), Tag(label: 'objectbox')]);
      }

      inspector.registerDatabaseSource(
        ObjectBoxBrowserSource(store, name: 'objectbox-demo'),
      );
      _objectboxRegistered = true;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ObjectBox demo seeded and registered!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ObjectBox seeding failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _makeNetworkRequest,
              child: const Text('Make Network Request'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _seedSqlite,
              child: const Text('Seed SQLite Demo'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _seedObjectBox,
              child: const Text('Seed ObjectBox Demo'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('Second Page')),
                      body: const Center(child: Text('Second Page')),
                    ),
                  ),
                );
              },
              child: const Text('Push New Route'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              // Throws an uncaught async error. With captureUncaughtErrors
              // enabled it is caught by PlatformDispatcher.instance.onError and
              // surfaces as a red error log in the Console tab — tap it to
              // expand the stack trace.
              onPressed: () => Future<void>.error(
                StateError('Demo: uncaught async error'),
                StackTrace.current,
              ),
              child: const Text('Throw Uncaught Error'),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
