import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reschool/services/deep_link_handler.dart';
import 'package:reschool/services/diary_navigation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => DiaryNavigationService.instance.consumeTab());
  for (final entry in {'schedule': 0, 'grades': 1, 'homework': 2}.entries) {
    test(
      'widget/${entry.key} queues the correct tab before home is mounted',
      () {
        DeepLinkHandler.handle(
          Uri.parse('reschool://widget/${entry.key}'),
          GlobalKey<NavigatorState>(),
        );
        expect(DiaryNavigationService.instance.consumeTab(), entry.value);
      },
    );
  }
  test('unknown widget routes are ignored', () {
    DeepLinkHandler.handle(
      Uri.parse('reschool://widget/unknown'),
      GlobalKey<NavigatorState>(),
    );
    expect(DiaryNavigationService.instance.consumeTab(), isNull);
  });
}
