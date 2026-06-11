/// Compares two cell values. Nulls are always treated as greater than any non-null
/// value (so they sort to the very end). Numbers are compared numerically, and other
/// types are compared as strings.
int compareCells(Object? a, Object? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;

  if (a is num && b is num) {
    return a.compareTo(b);
  }

  return a.toString().compareTo(b.toString());
}

/// Sorts the given [rows] by the column at [columnIndex].
/// If [ascending] is false, the order is reversed, but nulls remain at the end.
List<List<Object?>> sortRows(
  List<List<Object?>> rows,
  int columnIndex,
  bool ascending,
) {
  final copied = List<List<Object?>>.from(rows);
  copied.sort((rowA, rowB) {
    final a = rowA[columnIndex];
    final b = rowB[columnIndex];

    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;

    final cmp = compareCells(a, b);
    return ascending ? cmp : -cmp;
  });
  return copied;
}

/// Generates a preview string for a cell value.
/// Returns 'NULL' for null values, and truncates values longer than [maxLength].
String cellPreview(Object? value, {int maxLength = 100}) {
  if (value == null) return 'NULL';
  final str = value.toString();
  if (str.length <= maxLength) return str;
  return '${str.substring(0, maxLength)}…';
}
