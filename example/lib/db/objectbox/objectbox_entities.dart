import 'package:objectbox/objectbox.dart';

/// A demo entity, intentionally shaped like the sqflite `users` table so you
/// can see the same kind of data rendered from a non-SQL source.
@Entity()
class Note {
  Note({this.id = 0, required this.title, this.body});

  @Id()
  int id;

  String title;

  String? body;
}

/// A second entity, so `ObjectBoxBrowserSource.listTables()` has more than one
/// "table" to enumerate — mirroring the two-table sqflite demo.
@Entity()
class Tag {
  Tag({this.id = 0, required this.label});

  @Id()
  int id;

  String label;
}
