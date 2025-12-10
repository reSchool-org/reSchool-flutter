import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../viewmodels/diary_viewmodel.dart';
import '../providers/bell_schedule_provider.dart';
import '../widgets/week_strip.dart';
import '../widgets/lesson_card.dart';
import '../widgets/break_card.dart';
import '../utils/time_utils.dart';
import '../models/lesson_view_model.dart';

class DiaryScreen extends StatelessWidget {
  const DiaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DiaryViewModel(
        Provider.of<BellScheduleProvider>(context, listen: false),
      ),
      child: const DiaryView(),
    );
  }
}

class DiaryView extends StatefulWidget {
  const DiaryView({super.key});

  @override
  State<DiaryView> createState() => _DiaryViewState();
}

class _DiaryViewState extends State<DiaryView> {
  late PageController _pageController;
  final DateTime _anchorDate = DateTime(2020, 1, 1);
  bool _isProgrammaticPageChange = false;
  Timer? _timer;

  int _getDateIndex(DateTime date) {
    final startOfDate = DateTime(date.year, date.month, date.day);
    final startOfAnchor = DateTime(_anchorDate.year, _anchorDate.month, _anchorDate.day);
    return startOfDate.difference(startOfAnchor).inDays;
  }

  DateTime _getDateFromIndex(int index) {
    return _anchorDate.add(Duration(days: index));
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    
    _timer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final vm = context.read<DiaryViewModel>();
    final initialIndex = _getDateIndex(vm.selectedDate);
    if (_pageController.hasClients) {
       if ((_pageController.page?.round() ?? 0) != initialIndex && !_isProgrammaticPageChange) {
         _pageController.jumpToPage(initialIndex);
       }
    } else {
       _pageController = PageController(initialPage: initialIndex);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DiaryViewModel>();
    final theme = Theme.of(context);
    
    final targetIndex = _getDateIndex(vm.selectedDate);
    if (_pageController.hasClients) {
      final currentIndex = _pageController.page?.round() ?? targetIndex;
      if (currentIndex != targetIndex && !_isProgrammaticPageChange) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _isProgrammaticPageChange = true;
          _pageController.animateToPage(
            targetIndex, 
            duration: const Duration(milliseconds: 300), 
            curve: Curves.easeInOut,
          ).then((_) => _isProgrammaticPageChange = false);
        });
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () async {
             final picked = await showDatePicker(
               context: context,
               initialDate: vm.selectedDate,
               firstDate: DateTime(2020),
               lastDate: DateTime(2030),
             );
             if (picked != null) {
               vm.selectDate(picked);
             }
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.calendar_today, size: 18),
              const SizedBox(width: 8),
              Text(
                DateFormat('LLLL yyyy', 'ru').format(vm.selectedDate),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.today),
            onPressed: () => vm.selectDate(DateTime.now()),
            tooltip: "Сегодня",
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: theme.cardColor,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => vm.changeWeek(-1),
                    ),
                    Text(
                      "Неделя ${DateFormat('d MMMM', 'ru').format(vm.currentWeek.first)} - ${DateFormat('d MMMM', 'ru').format(vm.currentWeek.last)}",
                      style: theme.textTheme.bodySmall,
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => vm.changeWeek(1),
                    ),
                  ],
                ),
                WeekStrip(
                  week: vm.currentWeek,
                  selectedDate: vm.selectedDate,
                  onSelect: vm.selectDate,
                ),
              ],
            ),
          ),
          
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (index) {
                if (!_isProgrammaticPageChange) {
                   final newDate = _getDateFromIndex(index);
                   if (!vm.isSameDay(newDate, vm.selectedDate)) {
                     vm.selectDate(newDate);
                   }
                }
              },
              itemBuilder: (context, index) {
                final date = _getDateFromIndex(index);
                final lessons = vm.getLessonsForDate(date);

                if (vm.isLoading && lessons.isEmpty) {
                   return const Center(child: CircularProgressIndicator());
                }
                
                if (lessons.isEmpty) {
                   if (vm.error != null) {
                     return Center(child: Text("Ошибка: ${vm.error}"));
                   }
                   return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.weekend, size: 64, color: theme.colorScheme.outline.withOpacity(0.5)),
                          const SizedBox(height: 16),
                          Text(
                            "Нет уроков",
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    );
                }

                return _buildLessonList(context, lessons, date);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLessonList(BuildContext context, List<LessonViewModel> lessons, DateTime date) {
    final now = DateTime.now();
    final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
    final timeOfDay = TimeOfDay.fromDateTime(now);

    final List<Widget> items = [];

    for (int i = 0; i < lessons.length; i++) {
      final lesson = lessons[i];
      bool isNow = false;

      if (isToday) {
        if (lesson.startTime.isNotEmpty && lesson.endTime.isNotEmpty) {
          isNow = TimeUtils.isTimeBetween(lesson.startTime, lesson.endTime, timeOfDay);
        }
      }

      items.add(LessonCard(
        lesson: lesson,
        isNow: isNow,
        onTap: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => LessonDetailSheet(lesson: lesson),
          );
        },
      ));

      if (isToday && i < lessons.length - 1) {
        final nextLesson = lessons[i + 1];
        if (lesson.endTime.isNotEmpty && nextLesson.startTime.isNotEmpty) {
          final isBreakNow = TimeUtils.isTimeBetween(lesson.endTime, nextLesson.startTime, timeOfDay);
          
          if (isBreakNow) {
            final startMin = TimeUtils.toMinutes(lesson.endTime);
            final endMin = TimeUtils.toMinutes(nextLesson.startTime);
            final duration = endMin - startMin;

            items.add(BreakCard(
              start: lesson.endTime,
              end: nextLesson.startTime,
              duration: duration > 0 ? duration : 0,
            ));
          }
        }
      }
    }

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 20),
      children: items,
    );
  }
}
