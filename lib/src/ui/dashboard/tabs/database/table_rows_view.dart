import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../models/database_browser_source.dart';
import '../../../../utils/table_sort.dart';

/// A detailed full-page grid browser for a single database table.
class TableRowsView extends StatefulWidget {
  const TableRowsView({
    super.key,
    required this.source,
    required this.tableName,
  });

  final DatabaseBrowserSource source;
  final String tableName;

  @override
  State<TableRowsView> createState() => _TableRowsViewState();
}

class _TableRowsViewState extends State<TableRowsView> {
  bool _loading = true;
  String? _errorMessage;

  List<String> _columns = [];
  List<List<Object?>> _rows = [];
  int? _totalRows;
  int _lastPageSize = 0;

  int? _sortColumnIndex;
  bool _sortAscending = true;

  int _offset = 0;
  static const int _limit = 200;

  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadData(clearCurrent: true);
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  Future<void> _loadData({required bool clearCurrent}) async {
    setState(() {
      _loading = true;
      _errorMessage = null;
      if (clearCurrent) {
        _offset = 0;
        _rows.clear();
        _sortColumnIndex = null;
        _lastPageSize = 0;
      }
    });

    try {
      final page = await widget.source.fetchRows(
        widget.tableName,
        limit: _limit,
        offset: _offset,
      );

      if (mounted) {
        setState(() {
          _columns = page.columns;
          _rows.addAll(page.rows);
          _lastPageSize = page.rows.length;
          _totalRows = page.totalRows;

          if (_sortColumnIndex != null) {
            _rows = sortRows(_rows, _sortColumnIndex!, _sortAscending);
          }
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _loading = false;
        });
      }
    }
  }

  bool _hasMore() {
    if (_totalRows != null) {
      return _rows.length < _totalRows!;
    }
    return _lastPageSize == _limit;
  }

  void _handleSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
      _rows = sortRows(_rows, columnIndex, ascending);
    });
  }

  void _showCellDetails(Object? cell) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        final fullValue = cell?.toString() ?? 'NULL';
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Cell Details',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      fullValue,
                      style: cell == null
                          ? const TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Colors.grey,
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy Value'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: fullValue));
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Value copied to clipboard'),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final titleSuffix = _totalRows != null ? ' ($_totalRows rows)' : '';

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.tableName}$titleSuffix'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadData(clearCurrent: true),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _rows.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => _loadData(clearCurrent: true),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: _columns.isEmpty || _rows.isEmpty
              ? const Center(child: Text('No rows'))
              : Scrollbar(
                  controller: _verticalController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _verticalController,
                    scrollDirection: Axis.vertical,
                    child: Scrollbar(
                      controller: _horizontalController,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _horizontalController,
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          sortColumnIndex: _sortColumnIndex,
                          sortAscending: _sortAscending,
                          columns: _columns.map((col) {
                            return DataColumn(
                              label: Text(col),
                              onSort: (colIdx, ascending) =>
                                  _handleSort(colIdx, ascending),
                            );
                          }).toList(),
                          rows: _rows.map((row) {
                            return DataRow(
                              cells: row.map((cell) {
                                final preview = cellPreview(cell);
                                final isNull = cell == null;
                                return DataCell(
                                  Text(
                                    preview,
                                    style: isNull
                                        ? const TextStyle(
                                            fontStyle: FontStyle.italic,
                                            color: Colors.grey,
                                          )
                                        : null,
                                  ),
                                  onTap: () => _showCellDetails(cell),
                                );
                              }).toList(),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
        _buildStatusBar(),
      ],
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _totalRows != null
                ? 'Showing ${_rows.length} of $_totalRows'
                : 'Showing ${_rows.length}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_hasMore())
            if (_loading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              TextButton(
                onPressed: () {
                  _offset += _limit;
                  _loadData(clearCurrent: false);
                },
                child: const Text('Load More'),
              ),
        ],
      ),
    );
  }
}
