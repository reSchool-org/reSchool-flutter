import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../viewmodels/marks_viewmodel.dart';
import '../providers/bell_schedule_provider.dart';
import '../widgets/lesson_card.dart'; 

class MarksScreen extends StatelessWidget {
  const MarksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MarksViewModel(
        Provider.of<BellScheduleProvider>(context, listen: false),
      )..loadPeriods(),
      child: const _MarksView(),
    );
  }
}

class _MarksView extends StatelessWidget {
  const _MarksView();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MarksViewModel>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Оценки"),
        centerTitle: true,
      ),
      body: Column(
        children: [
          
          if (vm.allPeriods.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: MenuAnchor(
                builder: (context, controller, child) {
                  return InkWell(
                    onTap: () {
                      if (controller.isOpen) {
                        controller.close();
                      } else {
                        controller.open();
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            vm.selectedPeriod?.displayName ?? "Выберите период",
                            style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                          ),
                          Icon(Icons.arrow_drop_down, color: colorScheme.primary),
                        ],
                      ),
                    ),
                  );
                },
                menuChildren: vm.allPeriods.map((item) {
                  return MenuItemButton(
                    onPressed: () => vm.selectPeriod(item),
                    leadingIcon: vm.selectedPeriod == item ? const Icon(Icons.check, size: 18) : null,
                    child: Text(item.displayName),
                  );
                }).toList(),
              ),
            ),

          Expanded(
            child: Builder(
              builder: (context) {
                if (vm.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (vm.error != null) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(vm.error!, style: TextStyle(color: colorScheme.error), textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => vm.loadPeriods(),
                          child: const Text("Повторить"),
                        ),
                      ],
                    ),
                  );
                }

                if (vm.subjects.isEmpty) {
                  return Center(
                    child: Text("Нет данных", style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.outline)),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: vm.subjects.length,
                  itemBuilder: (context, index) {
                    final subject = vm.subjects[index];
                    return _SubjectRow(subject: subject);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SubjectRow extends StatelessWidget {
  final SubjectData subject;

  const _SubjectRow({required this.subject});

  Color _getMarkColor(String mark) {
    switch (mark) {
      case '5': return Colors.green;
      case '4': return Colors.blue;
      case '3': return Colors.orange;
      case '2': 
      case '1': return Colors.red;
      default: return Colors.grey;
    }
  }

  Color _getAvgColor(String avg) {
    final val = double.tryParse(avg);
    if (val == null) return Colors.grey;
    if (val >= 4.5) return Colors.green;
    if (val >= 3.5) return Colors.blue;
    if (val >= 2.5) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final Map<DateTime, List<MarkData>> grouped = {};
    for (var m in subject.marks) {
      final day = DateTime(m.date.year, m.date.month, m.date.day);
      if (!grouped.containsKey(day)) grouped[day] = [];
      grouped[day]!.add(m);
    }
    final sortedDates = grouped.keys.toList()..sort((a, b) => a.compareTo(b));

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      color: theme.cardColor, 
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            
            InkWell(
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => _SubjectDetailSheet(subject: subject),
                );
              },
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      subject.name,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (subject.average != "-")
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getAvgColor(subject.average),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        subject.average,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ),

            if (subject.marks.isNotEmpty) ...[
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: sortedDates.map((date) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Column(
                        children: [
                          Column(
                            children: grouped[date]!.map((mark) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: InkWell(
                                  onTap: () {
                                    
                                    showModalBottomSheet(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.transparent,
                                      builder: (context) => LessonDetailSheet(lesson: mark.lesson),
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: _getMarkColor(mark.value).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: _getMarkColor(mark.value),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Text(
                                      mark.value,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: _getMarkColor(mark.value), 
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat('d MMM', 'ru').format(date),
                            style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.outline),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ] else 
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text("Нет оценок", style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline)),
              ),
          ],
        ),
      ),
    );
  }
}

class _SubjectDetailSheet extends StatelessWidget {
  final SubjectData subject;

  const _SubjectDetailSheet({required this.subject});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(24),
          child: ListView(
            controller: scrollController,
            children: [
              Text(subject.name, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const Divider(height: 32),
              _buildRow(context, Icons.person, "Преподаватель", subject.teacher ?? "Не указан"),
              const SizedBox(height: 16),
              _buildRow(context, Icons.bar_chart, "Рейтинг", subject.rating ?? "Нет данных"),
              const SizedBox(height: 16),
              _buildRow(context, Icons.percent, "Средний балл", subject.average),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRow(BuildContext context, IconData icon, String title, String value) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, color: theme.colorScheme.primary),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }
}
