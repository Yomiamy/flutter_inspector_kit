import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inspector/flutter_inspector.dart';

// Enable the live system notification summarising network calls (opt-in).
// On Android this requires a notification icon + (Android 13+) the
// POST_NOTIFICATIONS permission; on iOS/macOS the user is prompted on init.
final inspector = FlutterInspector(showNetworkNotification: true);

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Inspector Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      navigatorObservers: [inspector.navigatorObserver],
      builder: (context, child) {
        return FlutterInspectorMagicalTap(
          onTap: () {
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
    _dio.interceptors.add(FlutterInspectorDioInterceptor(inspector));

    // Show FAB after frame builds
    WidgetsBinding.instance.addPostFrameCallback((_) {
      inspector.attach(context: context);
    });
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
      await _dio.get('https://jsonplaceholder.typicode.com/todos/1');
      inspector.log('Network request successful', level: LogLevel.info);
    } catch (e) {
      inspector.log('Network request failed: $e', level: LogLevel.error);
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
            const Text(
              'You have pushed the button this many times:',
            ),
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
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('Second Page')),
                          body: const Center(child: Text('Second Page')))),
                );
              },
              child: const Text('Push New Route'),
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
