import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/pin_service.dart';
import '../utils/app_font.dart';

// экран разблокировки по пин коду

/// показываем на старте, если пин задан, при успехе отдаём true,
/// false значит пользователь захотел войти паролем от аккаунта
class PinLockScreen extends StatefulWidget {
  const PinLockScreen({super.key});

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen>
    with TickerProviderStateMixin {
  static const int _pinLength = 4;

  String _entered = '';
  bool _hasError = false;
  bool _pinLocked = false;
  bool _verifying = false;
  bool _finished = false;
  bool _biometricsEnabled = false;
  bool _biometricsAvailable = false;

  late AnimationController _shakeController;
  late AnimationController _entranceController;
  late Animation<double> _entranceFade;
  late Animation<Offset> _entranceSlide;

  final _pinService = PinService();

  @override
  void initState() {
    super.initState();

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _entranceFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );
    _entranceSlide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 1.0, curve: Curves.easeOutCubic),
    ));

    _entranceController.forward();
    _loadBiometricsState();
    _loadPinLockState();
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  Future<void> _loadBiometricsState() async {
    final enabled = await _pinService.isBiometricsEnabled();
    final available = await _pinService.isBiometricsAvailable();
    if (mounted) {
      setState(() {
        _biometricsEnabled = enabled && available;
        _biometricsAvailable = available;
      });
      if (_biometricsEnabled) {
        await Future.delayed(const Duration(milliseconds: 400));
        _authenticateWithBiometrics();
      }
    }
  }

  Future<void> _loadPinLockState() async {
    final locked = await _pinService.isPinLocked();
    if (mounted) setState(() => _pinLocked = locked);
  }

  void _onDigit(String digit) {
    if (_pinLocked || _verifying || _entered.length >= _pinLength) return;
    HapticFeedback.selectionClick();
    setState(() {
      _entered += digit;
      _hasError = false;
    });
    if (_entered.length == _pinLength) {
      _verifyPin();
    }
  }

  void _onDelete() {
    if (_verifying || _entered.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _entered = _entered.substring(0, _entered.length - 1);
      _hasError = false;
    });
  }

  Future<void> _verifyPin() async {
    if (_verifying || _pinLocked) return;
    setState(() => _verifying = true);
    final ok = await _pinService.verifyPin(_entered);
    final locked = !ok && await _pinService.isPinLocked();
    if (!mounted) return;
    setState(() {
      _verifying = false;
      _pinLocked = locked;
    });
    if (ok) {
      _finish(true);
    } else {
      HapticFeedback.heavyImpact();
      _shakeController.forward(from: 0);
      setState(() {
        _entered = '';
        _hasError = true;
      });
    }
  }

  void _finish(bool unlocked) {
    if (!mounted || _finished) return;
    _finished = true;
    if (unlocked) HapticFeedback.lightImpact();
    Navigator.of(context).pop(unlocked);
  }

  Future<void> _authenticateWithBiometrics() async {
    if (!mounted || _finished) return;
    final ok = await _pinService.authenticateWithBiometrics();
    if (ok) _finish(true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final showBiometrics = _biometricsEnabled && _biometricsAvailable;

    return Scaffold(
      backgroundColor: cs.surface,
      body: FadeTransition(
        opacity: _entranceFade,
        child: SlideTransition(
          position: _entranceSlide,
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 48),
                // крупная иконка
                _HeroIcon(colorScheme: cs),
                const SizedBox(height: 24),
                // заголовок
                Text(
                  'reSchool',
                  style: appFont(context,
                    fontSize: 36,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 6),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.3),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: Text(
                    _pinLocked
                        ? 'Код заблокирован. Войдите по паролю'
                        : _hasError
                        ? 'Неверный код - попробуйте снова'
                        : 'Введите код-пароль для входа',
                    key: ValueKey((_hasError, _pinLocked)),
                    style: appFont(context,
                      fontSize: 15,
                      color: _hasError
                          ? cs.error
                          : cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                const SizedBox(height: 52),
                // точки пин кода
                _PinIndicators(
                  entered: _entered.length,
                  total: _pinLength,
                  hasError: _hasError,
                  shakeController: _shakeController,
                  colorScheme: cs,
                ),
                const Spacer(),
                // клавиатура
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: _Numpad(
                    onDigit: _onDigit,
                    onDelete: _onDelete,
                    onBiometrics: showBiometrics ? _authenticateWithBiometrics : null,
                    colorScheme: cs,
                  ),
                ),
                const SizedBox(height: 20),
                // запасной вход
                TextButton(
                  onPressed: () => _finish(false),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    'Войти по паролю',
                    style: appFont(context,
                      fontSize: 14,
                      color: cs.onSurface.withValues(alpha: 0.45),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// экран создания пин кода

/// пин заводим в два шага,
/// при сохранении возвращаем true, при отмене false
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen>
    with TickerProviderStateMixin {
  static const int _pinLength = 4;

  String _entered = '';
  String _firstPin = '';
  bool _isConfirming = false;
  bool _hasError = false;

  late AnimationController _shakeController;
  late AnimationController _stepController;

  @override
  void initState() {
    super.initState();

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _stepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _stepController.dispose();
    super.dispose();
  }

  void _onDigit(String digit) {
    if (_entered.length >= _pinLength) return;
    HapticFeedback.selectionClick();
    setState(() {
      _entered += digit;
      _hasError = false;
    });
    if (_entered.length == _pinLength) {
      Future.delayed(const Duration(milliseconds: 80), _onPinComplete);
    }
  }

  void _onDelete() {
    if (_entered.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _entered = _entered.substring(0, _entered.length - 1);
      _hasError = false;
    });
  }

  Future<void> _onPinComplete() async {
    if (!_isConfirming) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      setState(() {
        _firstPin = _entered;
        _entered = '';
        _isConfirming = true;
      });
      _stepController.forward();
    } else {
      if (_entered == _firstPin) {
        await Future.delayed(const Duration(milliseconds: 100));
        await PinService().setPin(_entered);
        HapticFeedback.lightImpact();
        if (mounted) Navigator.of(context).pop(true);
      } else {
        HapticFeedback.heavyImpact();
        _shakeController.forward(from: 0);
        setState(() {
          _entered = '';
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: cs.onSurface),
          onPressed: () => Navigator.of(context).pop(false),
          tooltip: 'Закрыть',
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 16),
            // индикатор шага
            _StepIndicator(
              currentStep: _isConfirming ? 1 : 0,
              totalSteps: 2,
              colorScheme: cs,
            ),
            const SizedBox(height: 32),
            // крупная иконка
            _HeroIcon(colorScheme: cs),
            const SizedBox(height: 24),
            // заголовок
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.15, 0),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                      parent: anim, curve: Curves.easeOutCubic)),
                  child: child,
                ),
              ),
              child: Text(
                _isConfirming ? 'Подтвердите код' : 'Создайте код-пароль',
                key: ValueKey(_isConfirming),
                style: appFont(context,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                  letterSpacing: -0.8,
                ),
              ),
            ),
            const SizedBox(height: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Text(
                _hasError
                    ? 'Коды не совпадают - попробуйте снова'
                    : _isConfirming
                        ? 'Введите код ещё раз'
                        : '4-значный числовой код',
                key: ValueKey('$_isConfirming$_hasError'),
                style: appFont(context,
                  fontSize: 15,
                  color: _hasError
                      ? cs.error
                      : cs.onSurface.withValues(alpha: 0.5),
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 48),
            // точки пин кода
            _PinIndicators(
              entered: _entered.length,
              total: _pinLength,
              hasError: _hasError,
              shakeController: _shakeController,
              colorScheme: cs,
            ),
            const Spacer(),
            // клавиатура
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: _Numpad(
                onDigit: _onDigit,
                onDelete: _onDelete,
                colorScheme: cs,
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// общие кусочки

/// крупная иконка со скруглёнными углами, как логотип на экране входа
class _HeroIcon extends StatelessWidget {
  final ColorScheme colorScheme;

  const _HeroIcon({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(
        Icons.school_rounded,
        size: 40,
        color: colorScheme.primary,
      ),
    );
  }
}

/// индикатор шага в виде пилюли
class _StepIndicator extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final ColorScheme colorScheme;

  const _StepIndicator({
    required this.currentStep,
    required this.totalSteps,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(totalSteps, (i) {
        final active = i == currentStep;
        final done = i < currentStep;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutBack,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 32 : 8,
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: done || active
                ? colorScheme.primary
                : colorScheme.outlineVariant,
          ),
        );
      }),
    );
  }
}

/// ряд точек пин кода, при ошибке дёргается
class _PinIndicators extends StatelessWidget {
  final int entered;
  final int total;
  final bool hasError;
  final AnimationController shakeController;
  final ColorScheme colorScheme;

  const _PinIndicators({
    required this.entered,
    required this.total,
    required this.hasError,
    required this.shakeController,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: shakeController,
      builder: (context, child) {
        final shake = math.sin(shakeController.value * 12 * math.pi) * 14.0;
        return Transform.translate(offset: Offset(shake, 0), child: child);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(total, (i) => _PinDot(
          key: ValueKey(i),
          filled: i < entered,
          isNext: i == entered,
          hasError: hasError,
          colorScheme: colorScheme,
        )),
      ),
    );
  }
}

/// одна анимированная точка пин кода, пружинка в духе M3 Expressive
/// область нажатия фиксированные 32×32, чтобы при анимации ничего не прыгало
/// слои снизу вверх:
/// 1. дорожка, видна всегда, маленькая (10 px), приглушённая
/// 2. заливка, приезжает и уезжает по [Curves.elasticOut]
class _PinDot extends StatefulWidget {
  final bool filled;
  final bool isNext; // сюда встанет следующая цифра
  final bool hasError;
  final ColorScheme colorScheme;

  const _PinDot({
    super.key,
    required this.filled,
    required this.isNext,
    required this.hasError,
    required this.colorScheme,
  });

  @override
  State<_PinDot> createState() => _PinDotState();
}

class _PinDotState extends State<_PinDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  // пружина: масштаб от 0 до 1.0, кривая подскакивает примерно до 1.25 и успокаивается
  late final Animation<double> _spring = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.elasticOut,        // заливка, пружинит
    reverseCurve: Curves.easeInCubic, // удаление, резко схлопывается
  );

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
      reverseDuration: const Duration(milliseconds: 160),
    );
    // состояние восстанавливаем мгновенно, например после смены шага
    if (widget.filled) _ctrl.value = 1.0;
  }

  @override
  void didUpdateWidget(_PinDot old) {
    super.didUpdateWidget(old);
    if (!old.filled && widget.filled) {
      _ctrl.forward(from: 0.0);           // цифру ввели, точка выпрыгивает
    } else if (old.filled && !widget.filled) {
      _ctrl.reverse();                     // цифру стёрли, точка схлопывается
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.colorScheme;

    // цвет дорожки: пусто приглушённый, следующая чуть ярче, ошибка красный
    final trackColor = widget.hasError
        ? cs.error.withValues(alpha: 0.35)
        : widget.isNext && !widget.filled
            ? cs.primary.withValues(alpha: 0.30)
            : cs.onSurface.withValues(alpha: 0.18);

    final fillColor =
        widget.hasError ? cs.error : cs.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11),
      child: SizedBox(
        width: 28,
        height: 28,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // слой 1: дорожка, видна всегда
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: trackColor,
              ),
            ),

            // слой 2: пружинящая заливка
            ScaleTransition(
              scale: _spring,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fillColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// цифровая клавиатура
class _Numpad extends StatelessWidget {
  final void Function(String) onDigit;
  final VoidCallback onDelete;
  final VoidCallback? onBiometrics;
  final ColorScheme colorScheme;

  const _Numpad({
    required this.onDigit,
    required this.onDelete,
    this.onBiometrics,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    const gap = 12.0;
    return Column(
      children: [
        _buildRow(context, ['1', '2', '3'], gap),
        const SizedBox(height: gap),
        _buildRow(context, ['4', '5', '6'], gap),
        const SizedBox(height: gap),
        _buildRow(context, ['7', '8', '9'], gap),
        const SizedBox(height: gap),
        Row(
          children: [
            // биометрия или заглушка
            Expanded(
              child: onBiometrics != null
                  ? _NumpadKey(
                      onTap: onBiometrics!,
                      colorScheme: colorScheme,
                      isSpecial: true,
                      child: Icon(
                        Icons.fingerprint_rounded,
                        size: 30,
                        color: colorScheme.secondary,
                      ),
                    )
                  : const SizedBox(),
            ),
            const SizedBox(width: gap),
            Expanded(
              child: _NumpadKey(
                onTap: () => onDigit('0'),
                colorScheme: colorScheme,
                child: Text(
                  '0',
                  style: appFont(context,
                    fontSize: 28,
                    fontWeight: FontWeight.w400,
                    color: colorScheme.onSurface,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
            const SizedBox(width: gap),
            Expanded(
              child: _NumpadKey(
                onTap: onDelete,
                colorScheme: colorScheme,
                isDelete: true,
                child: Icon(
                  Icons.backspace_outlined,
                  size: 26,
                  color: colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRow(BuildContext context, List<String> digits, double gap) {
    return Row(
      children: digits.asMap().entries.map((e) {
        final d = e.value;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              left: e.key == 0 ? 0 : gap / 2,
              right: e.key == digits.length - 1 ? 0 : gap / 2,
            ),
            child: _NumpadKey(
              onTap: () => onDigit(d),
              colorScheme: colorScheme,
              child: Text(
                d,
                style: appFont(context,
                  fontSize: 28,
                  fontWeight: FontWeight.w400,
                  color: colorScheme.onSurface,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// одна кнопка клавиатуры с анимацией нажатия в духе M3 Expressive
class _NumpadKey extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final ColorScheme colorScheme;
  final bool isSpecial;
  final bool isDelete;

  const _NumpadKey({
    required this.child,
    required this.onTap,
    required this.colorScheme,
    this.isSpecial = false,
    this.isDelete = false,
  });

  @override
  State<_NumpadKey> createState() => _NumpadKeyState();
}

class _NumpadKeyState extends State<_NumpadKey>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  Color get _bgColor {
    if (widget.isSpecial) {
      return widget.colorScheme.secondaryContainer
          .withValues(alpha: 0.7);
    }
    return widget.colorScheme.surfaceContainerHighest;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _scaleController.forward(),
      onTapUp: (_) {
        _scaleController.reverse();
        widget.onTap();
      },
      onTapCancel: () => _scaleController.reverse(),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            color: _bgColor,
            borderRadius: BorderRadius.circular(20),
          ),
          alignment: Alignment.center,
          child: widget.child,
        ),
      ),
    );
  }
}
