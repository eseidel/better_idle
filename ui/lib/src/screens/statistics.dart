import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/widgets/navigation_drawer.dart';
import 'package:better_idle/src/widgets/style.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';

class StatisticsPage extends StatelessWidget {
  const StatisticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      drawer: const AppNavigationDrawer(),
      body: StoreConnector<GlobalState, _StatisticsViewModel>(
        converter: (store) => _StatisticsViewModel(store.state),
        builder: (context, viewModel) {
          return ListView(
            children: [
              const _SectionHeader(title: 'General'),
              _StatRow(label: 'Total XP', value: viewModel.formattedTotalXp),
              _StatRow(
                label: 'Total Mastery Level',
                value: viewModel.formattedTotalMasteryLevel,
              ),
              _StatRow(
                label: 'Total Mastery XP',
                value: viewModel.formattedTotalMasteryXp,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatisticsViewModel {
  _StatisticsViewModel(this._state);

  final GlobalState _state;

  int get totalXp {
    var total = 0;
    for (final skill in Skill.values) {
      total += _state.skillState(skill).xp;
    }
    return total;
  }

  int get totalMasteryLevel {
    var total = 0;
    for (final actionState in _state.actionStates.values) {
      total += actionState.masteryLevel;
    }
    return total;
  }

  int get totalMasteryXp {
    var total = 0;
    for (final actionState in _state.actionStates.values) {
      total += actionState.masteryXp;
    }
    return total;
  }

  String get formattedTotalXp => preciseNumberString(totalXp);
  String get formattedTotalMasteryLevel =>
      preciseNumberString(totalMasteryLevel);
  String get formattedTotalMasteryXp => preciseNumberString(totalMasteryXp);
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Style.categoryHeaderColor,
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
