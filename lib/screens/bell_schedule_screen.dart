import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/bell_schedule_provider.dart';

class BellScheduleScreen extends StatelessWidget {
  const BellScheduleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Звонки'),
        centerTitle: true,
      ),
      body: Consumer<BellScheduleProvider>(
        builder: (context, provider, child) {
          final sortedLessons = provider.sortedLessonNumbers;
          final currentPresetId = provider.currentPresetId;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildPresetSelector(context, provider),
              const SizedBox(height: 16),
              
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.timer_outlined, color: Theme.of(context).colorScheme.secondary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Коррекция времени',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  provider.timeOffset == 0 
                                    ? 'Звонок звенит вовремя'
                                    : provider.timeOffset > 0
                                      ? 'Звонок отстаёт на ${provider.timeOffset} мин'
                                      : 'Звонок спешит на ${-provider.timeOffset} мин',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${provider.timeOffset > 0 ? '+' : ''}${provider.timeOffset} мин',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Slider(
                        value: provider.timeOffset.toDouble(),
                        min: -15,
                        max: 15,
                        divisions: 30,
                        label: '${provider.timeOffset > 0 ? '+' : ''}${provider.timeOffset}',
                        onChanged: (val) {
                          provider.setTimeOffset(val.round());
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              const Text(
                'РАСПИСАНИЕ ЗВОНКОВ',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    if (sortedLessons.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Нет уроков'),
                      )
                    else
                      ...sortedLessons.map((lessonNum) {
                        
                        final time = provider.getLessonTime(lessonNum, applyOffset: false);
                        if (time == null) return const SizedBox.shrink();

                        return Column(
                          children: [
                            ListTile(
                              title: Text('$lessonNum урок'),
                              subtitle: Text('${time.start} — ${time.end}'),
                              trailing: Icon(
                                Icons.edit_rounded,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              onTap: () => _editLessonTime(context, provider, lessonNum, time),
                            ),
                            if (lessonNum != sortedLessons.last)
                              Divider(
                                height: 1,
                                indent: 16,
                                endIndent: 16,
                                color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                              ),
                          ],
                        );
                      }),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              if (currentPresetId == 'custom')
                Center(
                  child: TextButton.icon(
                    onPressed: () => _showResetDialog(context, provider),
                    icon: const Icon(Icons.restore),
                    label: const Text('Сбросить по умолчанию'),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPresetSelector(BuildContext context, BellScheduleProvider provider) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showPresetPicker(context, provider),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.schedule_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Выбрать пресет',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      provider.currentPresetName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded),
            ],
          ),
        ),
      ),
    );
  }

  void _showPresetPicker(BuildContext context, BellScheduleProvider provider) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Выберите расписание',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: BellScheduleProvider.presets.length,
                  itemBuilder: (ctx, index) {
                    final preset = BellScheduleProvider.presets[index];
                    final isSelected = provider.currentPresetId == preset.id;
                    
                    return ListTile(
                      leading: isSelected 
                        ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)
                        : const Icon(Icons.circle_outlined),
                      title: Text(preset.name),
                      subtitle: preset.subtitle != null ? Text(preset.subtitle!) : null,
                      onTap: () {
                        provider.applyPreset(preset.id);
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editLessonTime(
    BuildContext context, 
    BellScheduleProvider provider, 
    int lessonNum, 
    LessonTime currentTime
  ) async {
    final startController = TextEditingController(text: currentTime.start);
    final endController = TextEditingController(text: currentTime.end);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Редактировать $lessonNum урок'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: startController,
              decoration: const InputDecoration(
                labelText: 'Начало (ЧЧ:ММ)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.datetime,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: endController,
              decoration: const InputDecoration(
                labelText: 'Конец (ЧЧ:ММ)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.datetime,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              
              provider.setLessonTime(
                lessonNum, 
                LessonTime(start: startController.text, end: endController.text)
              );
              Navigator.pop(ctx);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  Future<void> _showResetDialog(BuildContext context, BellScheduleProvider provider) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сбросить?'),
        content: const Text('Вернуть стандартное расписание?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      provider.resetToDefault();
    }
  }
}
