/// данные о закреплённом виджете зависят от платформы
class HomeWidgetInfo {
  /// размер доступен только на ios
  String? iOSFamily;

  /// строка конфигурации доступна только на ios
  String? iOSKind;

  /// на android идентификатор относится к отдельному экземпляру виджета
  int? androidWidgetId;

  /// имя класса доступно только на android
  String? androidClassName;

  /// на android берём локализованное название из выбора виджетов
  String? androidLabel;

  /// на ios конфигурацию WidgetConfigurationIntent нужно передать самому виджету
  Map<String, dynamic>? configuration;

  HomeWidgetInfo({
    this.iOSFamily,
    this.iOSKind,
    this.androidWidgetId,
    this.androidClassName,
    this.androidLabel,
    this.configuration,
  });

  factory HomeWidgetInfo.fromMap(Map<String, dynamic> data) {
    return HomeWidgetInfo(
      iOSFamily: data['family'] as String?,
      iOSKind: data['kind'] as String?,
      androidWidgetId: data['widgetId'] as int?,
      androidClassName: data['androidClassName'] as String?,
      androidLabel: data['label'] as String?,
      configuration:
          ((data['configuration'] as Map<dynamic, dynamic>?)
                ?..removeWhere((key, _) => key is! String))
              ?.cast<String, dynamic>(),
    );
  }

  @override
  String toString() {
    return 'HomeWidgetInfo('
        'iOSFamily: $iOSFamily, '
        'iOSKind: $iOSKind, '
        'androidWidgetId: $androidWidgetId, '
        'androidClassName: $androidClassName, '
        'androidLabel: $androidLabel, '
        'configuration: $configuration'
        ')';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is HomeWidgetInfo &&
        other.iOSFamily == iOSFamily &&
        other.iOSKind == iOSKind &&
        other.androidWidgetId == androidWidgetId &&
        other.androidClassName == androidClassName &&
        other.androidLabel == androidLabel &&
        other.configuration == configuration;
  }

  @override
  int get hashCode {
    return iOSFamily.hashCode ^
        iOSKind.hashCode ^
        androidWidgetId.hashCode ^
        androidClassName.hashCode ^
        androidLabel.hashCode ^
        configuration.hashCode;
  }
}
