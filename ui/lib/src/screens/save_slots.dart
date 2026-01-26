import 'package:flutter/material.dart';
import 'package:ui/src/services/save_slot_service.dart';
import 'package:ui/src/widgets/game_scaffold.dart';

/// Screen for managing save slots.
class SaveSlotsPage extends StatefulWidget {
  const SaveSlotsPage({super.key});

  @override
  State<SaveSlotsPage> createState() => _SaveSlotsPageState();
}

class _SaveSlotsPageState extends State<SaveSlotsPage> {
  SaveSlotMeta? _meta;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  Future<void> _loadMeta() async {
    final meta = await SaveSlotService.loadMeta();
    if (mounted) {
      setState(() {
        _meta = meta;
        _isLoading = false;
      });
    }
  }

  Future<void> _selectSlot(int slot) async {
    final manager = SaveSlotManager.of(context);
    if (slot == manager.activeSlot) return;

    await manager.switchSlot(slot);
    await _loadMeta();
  }

  Future<void> _deleteSlot(int slot) async {
    final manager = SaveSlotManager.of(context);
    final isActive = slot == manager.activeSlot;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Slot ${slot + 1}?'),
        content: Text(
          isActive
              ? 'This will erase all progress in the current slot and start '
                    'fresh. This cannot be undone.'
              : 'This will erase all progress in this slot. '
                    'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if ((confirmed ?? false) && mounted) {
      await manager.deleteSlot(slot);
      await _loadMeta();
    }
  }

  String _formatLastPlayed(DateTime? lastPlayed) {
    if (lastPlayed == null) return '';

    final now = DateTime.timestamp();
    final diff = now.difference(lastPlayed);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inHours < 1) {
      final mins = diff.inMinutes;
      return '$mins ${mins == 1 ? 'minute' : 'minutes'} ago';
    } else if (diff.inDays < 1) {
      final hours = diff.inHours;
      return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
    } else if (diff.inDays < 30) {
      final days = diff.inDays;
      return '$days ${days == 1 ? 'day' : 'days'} ago';
    } else {
      final months = diff.inDays ~/ 30;
      return '$months ${months == 1 ? 'month' : 'months'} ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: const Text('Save Slots'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildSlotList(),
    );
  }

  Widget _buildSlotList() {
    final manager = SaveSlotManager.of(context);
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: saveSlotCount,
      itemBuilder: (context, index) {
        final slotInfo = _meta?.slots[index];
        final isEmpty = slotInfo?.isEmpty ?? true;
        final isActive = index == manager.activeSlot;

        return _SaveSlotCard(
          slotIndex: index,
          isEmpty: isEmpty,
          isActive: isActive,
          lastPlayed: slotInfo?.lastPlayed,
          lastPlayedFormatted: _formatLastPlayed(slotInfo?.lastPlayed),
          onTap: () => _selectSlot(index),
          onDelete: isEmpty ? null : () => _deleteSlot(index),
        );
      },
    );
  }
}

class _SaveSlotCard extends StatelessWidget {
  const _SaveSlotCard({
    required this.slotIndex,
    required this.isEmpty,
    required this.isActive,
    required this.lastPlayed,
    required this.lastPlayedFormatted,
    required this.onTap,
    this.onDelete,
  });

  final int slotIndex;
  final bool isEmpty;
  final bool isActive;
  final DateTime? lastPlayed;
  final String lastPlayedFormatted;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isActive
            ? BorderSide(color: colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Slot ${slotIndex + 1}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Active',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onPrimary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (isEmpty)
                      Text(
                        'Empty - Tap to start new game',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    else
                      Text(
                        'Last played: $lastPlayedFormatted',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (onDelete != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onDelete,
                  tooltip: 'Delete slot',
                ),
            ],
          ),
        ),
      ),
    );
  }
}
