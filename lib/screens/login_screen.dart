import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _isLoading = false;
  bool _rememberMe = false;
  bool _obscurePassword = true;
  final ApiService _api = ApiService();

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _checkAutoLogin();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _checkAutoLogin() async {
    setState(() => _isLoading = true);
    final success = await _api.attemptAutoLogin();
    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        _navigateToHome();
      }
    }
  }

  Future<void> _handleLogin() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final l10n = AppLocalizations.of(context)!;

    if (username.isEmpty || password.isEmpty) {
      _showError(l10n.enterCredentials);
      return;
    }

    setState(() => _isLoading = true);

    final success =
        await _api.login(username, password, rememberMe: _rememberMe);

    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        HapticFeedback.lightImpact();
        _navigateToHome();
      } else {
        HapticFeedback.heavyImpact();
        _showError(l10n.invalidCredentials);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: Theme.of(context).colorScheme.error,
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _navigateToHome() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const HomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  Widget _buildKeyboardDoneButton() {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    if (bottomInset <= 0) return const SizedBox.shrink();

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Align(
            alignment: Alignment.bottomRight,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: IconButton(
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                onPressed: _dismissKeyboard,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return GestureDetector(
      onTap: _dismissKeyboard,
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: Stack(
          children: [
            SafeArea(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Center(
                    child: SingleChildScrollView(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 48),

                            _buildLogo(colorScheme, isDark, l10n),

                            const SizedBox(height: 64),

                            _buildLoginForm(colorScheme, isDark, l10n),

                            const SizedBox(height: 48),

                            _buildFooter(colorScheme, l10n),

                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _buildKeyboardDoneButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildLogo(ColorScheme colorScheme, bool isDark, AppLocalizations l10n) {
    return Column(
      children: [

        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: colorScheme.primary.withOpacity(0.2),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withOpacity(0.15),
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
        ),

        const SizedBox(height: 24),

        Text(
          'reSchool',
          style: GoogleFonts.outfit(
            fontSize: 36,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
            letterSpacing: -1,
          ),
        ),

        const SizedBox(height: 8),

        Text(
          l10n.electronicDiary,
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w400,
            color: colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginForm(ColorScheme colorScheme, bool isDark, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [

        _buildTextField(
          controller: _usernameController,
          focusNode: _usernameFocus,
          hint: l10n.username,
          icon: Icons.person_outline_rounded,
          colorScheme: colorScheme,
          isDark: isDark,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _passwordFocus.requestFocus(),
        ),

        const SizedBox(height: 16),

        _buildTextField(
          controller: _passwordController,
          focusNode: _passwordFocus,
          hint: l10n.password,
          icon: Icons.lock_outline_rounded,
          colorScheme: colorScheme,
          isDark: isDark,
          isPassword: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _handleLogin(),
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: colorScheme.onSurface.withOpacity(0.4),
              size: 20,
            ),
            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),

        const SizedBox(height: 20),

        GestureDetector(
          onTap: () => setState(() => _rememberMe = !_rememberMe),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: _rememberMe
                      ? colorScheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _rememberMe
                        ? colorScheme.primary
                        : colorScheme.onSurface.withOpacity(0.2),
                    width: 1.5,
                  ),
                ),
                child: _rememberMe
                    ? Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: colorScheme.onPrimary,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Text(
                l10n.rememberMe,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),

        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 56,
          child: FilledButton(
            onPressed: _isLoading ? null : _handleLogin,
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              disabledBackgroundColor: colorScheme.primary.withOpacity(0.6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
            child: _isLoading
                ? SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: colorScheme.onPrimary,
                    ),
                  )
                : Text(
                    l10n.login,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required IconData icon,
    required ColorScheme colorScheme,
    required bool isDark,
    bool isPassword = false,
    TextInputAction? textInputAction,
    void Function(String)? onSubmitted,
    Widget? suffixIcon,
  }) {
    final fillColor = isDark
        ? colorScheme.onSurface.withOpacity(0.05)
        : colorScheme.onSurface.withOpacity(0.04);

    final borderColor = colorScheme.onSurface.withOpacity(0.08);

    return Container(
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        obscureText: isPassword && _obscurePassword,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        style: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: colorScheme.onSurface,
        ),
        cursorColor: colorScheme.primary,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w400,
            color: colorScheme.onSurface.withOpacity(0.4),
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 16, right: 12),
            child: Icon(
              icon,
              size: 20,
              color: colorScheme.onSurface.withOpacity(0.4),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 48,
            minHeight: 48,
          ),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(ColorScheme colorScheme, AppLocalizations l10n) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildThemeButton(
              icon: Icons.light_mode_outlined,
              isSelected: Provider.of<ThemeProvider>(context).themeMode ==
                  ThemeMode.light,
              onTap: () => Provider.of<ThemeProvider>(context, listen: false)
                  .setTheme(ThemeMode.light),
              colorScheme: colorScheme,
            ),
            const SizedBox(width: 8),
            _buildThemeButton(
              icon: Icons.dark_mode_outlined,
              isSelected: Provider.of<ThemeProvider>(context).themeMode ==
                  ThemeMode.dark,
              onTap: () => Provider.of<ThemeProvider>(context, listen: false)
                  .setTheme(ThemeMode.dark),
              colorScheme: colorScheme,
            ),
            const SizedBox(width: 8),
            _buildThemeButton(
              icon: Icons.contrast_outlined,
              isSelected: Provider.of<ThemeProvider>(context).themeMode ==
                  ThemeMode.system,
              onTap: () => Provider.of<ThemeProvider>(context, listen: false)
                  .setTheme(ThemeMode.system),
              colorScheme: colorScheme,
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          '${l10n.version} 1.0.1',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: colorScheme.onSurface.withOpacity(0.3),
          ),
        ),
      ],
    );
  }

  Widget _buildThemeButton({
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primary.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary.withOpacity(0.3)
                : colorScheme.onSurface.withOpacity(0.1),
            width: 1,
          ),
        ),
        child: Icon(
          icon,
          size: 20,
          color: isSelected
              ? colorScheme.primary
              : colorScheme.onSurface.withOpacity(0.4),
        ),
      ),
    );
  }
}