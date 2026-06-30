import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';
import 'package:path_provider/path_provider.dart';

import '../db/objectbox/objectbox.g.dart';
import '../db/objectbox/objectbox_browser_source.dart';
import '../db/objectbox/objectbox_entities.dart';

/// Demonstrates browsing an ObjectBox store in the inspector.
///
/// Owns the store handle and registration state. Call [seed] from a button,
/// [dispose] from the State's dispose().
class ObjectBoxDemo {
  ObjectBoxDemo(this._inspector);

  final FlutterInspector _inspector;
  bool _registered = false;
  Store? _store;

  /// Opens the store, seeds it if empty, and registers it with the inspector.
  ///
  /// Returns a status message for the caller to surface (e.g. via SnackBar).
  /// On web this returns an explanatory message without opening anything, since
  /// ObjectBox relies on native libraries and does not support web.
  Future<String?> seed() async {
    if (kIsWeb) {
      return 'ObjectBox is not supported on web. '
          'Run this demo on a mobile or desktop target.';
    }
    if (_registered) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final store = await openStore(directory: '${dir.path}/objectbox-demo');
      _store = store;

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

      _inspector.registerDatabaseSource(
        ObjectBoxBrowserSource(store, name: 'objectbox-demo'),
      );
      _registered = true;
      return 'ObjectBox demo seeded and registered!';
    } catch (e) {
      return 'ObjectBox seeding failed: $e';
    }
  }

  void dispose() {
    _store?.close();
  }
}
