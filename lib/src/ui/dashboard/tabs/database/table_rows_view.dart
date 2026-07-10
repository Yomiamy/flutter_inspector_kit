import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../models/database_browser_source.dart';
import '../../../../utils/table_sort.dart';
import '../../../theme/inspector_theme.dart';
import '../../../widgets/error_card.dart';

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
  bool _isFetching = false;
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
    if (_isFetching) return;
    _isFetching = true;

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
    } finally {
      _isFetching = false;
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
      builder: (context) => _CellDetailsBottomSheet(cell: cell),
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
      body: _TableRowsBody(
        loading: _loading,
        errorMessage: _errorMessage,
        columns: _columns,
        rows: _rows,
        sortColumnIndex: _sortColumnIndex,
        sortAscending: _sortAscending,
        verticalController: _verticalController,
        horizontalController: _horizontalController,
        onRetry: () => _loadData(clearCurrent: true),
        onSort: _handleSort,
        onTapCell: _showCellDetails,
        statusBar: _StatusBar(
          loadedRowsCount: _rows.length,
          totalRows: _totalRows,
          hasMore: _hasMore(),
          loading: _loading,
          onLoadMore: () {
            _offset += _limit;
            _loadData(clearCurrent: false);
          },
        ),
      ),
    );
  }
}

class _CellDetailsBottomSheet extends StatelessWidget {
  const _CellDetailsBottomSheet({required this.cell});

  final Object? cell;

  @override
  Widget build(BuildContext context) {
    final fullValue = cell?.toString() ?? 'NULL';
    return SafeArea(
      child: Padding(
        padding: ThemePadding.paddingAll16,
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
            Flexible(
              child: SingleChildScrollView(
                child: SelectableText(
                  fullValue,
                  style: cell == null
                      ? ThemeTextStyle.mutedStyle.copyWith(
                          fontStyle: FontStyle.italic,
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(height: ThemeSpacing.spacing16),
            ElevatedButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('Copy Value'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: fullValue));
                if (context.mounted) {
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(context);
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Value copied to clipboard')),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.loadedRowsCount,
    required this.totalRows,
    required this.hasMore,
    required this.loading,
    required this.onLoadMore,
  });

  final int loadedRowsCount;
  final int? totalRows;
  final bool hasMore;
  final bool loading;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: ThemePadding.paddingH16V8,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            totalRows != null
                ? 'Showing $loadedRowsCount of $totalRows'
                : 'Showing $loadedRowsCount',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (hasMore)
            if (loading)
              const SizedBox(
                width: ThemeSize.size20,
                height: ThemeSize.size20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              TextButton(onPressed: onLoadMore, child: const Text('Load More')),
        ],
      ),
    );
  }
}

class _TableRowsBody extends StatelessWidget {
  const _TableRowsBody({
    required this.loading,
    required this.errorMessage,
    required this.columns,
    required this.rows,
    required this.sortColumnIndex,
    required this.sortAscending,
    required this.verticalController,
    required this.horizontalController,
    required this.onRetry,
    required this.onSort,
    required this.onTapCell,
    required this.statusBar,
  });

  final bool loading;
  final String? errorMessage;
  final List<String> columns;
  final List<List<Object?>> rows;
  final int? sortColumnIndex;
  final bool sortAscending;
  final ScrollController verticalController;
  final ScrollController horizontalController;
  final VoidCallback onRetry;
  final void Function(int columnIndex, bool ascending) onSort;
  final void Function(Object? cell) onTapCell;
  final Widget statusBar;

  @override
  Widget build(BuildContext context) {
    if (loading && rows.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMessage != null && rows.isEmpty) {
      return ErrorCard(message: errorMessage!, onRetry: onRetry);
    }

    return Column(
      children: [
        Expanded(
          child: columns.isEmpty || rows.isEmpty
              ? const Center(child: Text('No rows'))
              : Scrollbar(
                  controller: verticalController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: verticalController,
                    scrollDirection: Axis.vertical,
                    child: Scrollbar(
                      controller: horizontalController,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: horizontalController,
                        scrollDirection: Axis.horizontal,
                        child: Padding(
                          padding: const EdgeInsets.only(
                            bottom: ThemeSpacing.spacing16,
                          ),
                          child: DataTable(
                            sortColumnIndex: sortColumnIndex,
                            sortAscending: sortAscending,
                            columns: columns.map((col) {
                              return DataColumn(
                                label: Text(col),
                                onSort: onSort,
                              );
                            }).toList(),
                            rows: rows.map((row) {
                              return DataRow(
                                cells: row.map((cell) {
                                  final preview = cellPreview(cell);
                                  final isNull = cell == null;
                                  return DataCell(
                                    Text(
                                      preview,
                                      style: isNull
                                          ? ThemeTextStyle.mutedStyle.copyWith(
                                              fontStyle: FontStyle.italic,
                                            )
                                          : null,
                                    ),
                                    onTap: () => onTapCell(cell),
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
        ),
        statusBar,
      ],
    );
  }
}

