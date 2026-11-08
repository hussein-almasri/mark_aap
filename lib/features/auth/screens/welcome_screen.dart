import 'package:flutter/material.dart';

import 'login_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const _background = Color(0xFF0D4036);
  static const _mint = Color(0xFFB7D9CE);

  void _openLogin(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _background,
        body: Stack(
          children: [
            const Positioned(
              top: -110,
              left: -90,
              child: _BackgroundCircle(size: 270),
            ),
            const Positioned(
              top: 170,
              left: -145,
              child: _BackgroundCircle(size: 260, opacity: 0.035),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 18,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildBrand(context),
                                const SizedBox(
                                  height: 236,
                                  child: CustomPaint(
                                    painter: _ShelvesIllustrationPainter(),
                                  ),
                                ),
                                Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 10,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text(
                                            'كل شيء مرتب',
                                            style: TextStyle(
                                              color: _background,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Icon(
                                            Icons.check_circle,
                                            size: 19,
                                            color: _background.withValues(
                                              alpha: 0.78,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'إدارة أوضح.\nقرارات أذكى.',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 32,
                                    height: 1.28,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'نظم المنتجات والفواتير والديون والمصاريف من مكان واحد. يمكنك أن تبدأ بإدارة البيع.',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    color: _mint,
                                    fontSize: 14,
                                    height: 1.8,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                SizedBox(
                                  height: 54,
                                  child: FilledButton.icon(
                                    onPressed: () => _openLogin(context),
                                    icon: const Icon(Icons.arrow_forward),
                                    label: const Text(
                                      'تسجيل الدخول',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: _background,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrand(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Text(
            'ر',
            style: TextStyle(
              color: _background,
              fontSize: 29,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'رَفّ',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                height: 1.1,
              ),
            ),
            Text(
              'إدارة أعمالك ببساطة',
              style: TextStyle(
                color: _mint.withValues(alpha: 0.9),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BackgroundCircle extends StatelessWidget {
  const _BackgroundCircle({required this.size, this.opacity = 0.045});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: opacity),
            width: 28,
          ),
        ),
      ),
    );
  }
}

class _ShelvesIllustrationPainter extends CustomPainter {
  const _ShelvesIllustrationPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final shelfPaint = Paint()
      ..color = const Color(0xFFF7F3E9)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.square;
    final colors = [
      const Color(0xFFD58D69),
      const Color(0xFF91B7A9),
      const Color(0xFFE6D2A6),
    ];

    for (var shelf = 0; shelf < 2; shelf++) {
      final baseline = size.height * (shelf == 0 ? 0.43 : 0.87);
      final blockHeight = size.height * (shelf == 0 ? 0.27 : 0.29);
      final blockWidth = size.width * 0.15;

      for (var item = 0; item < colors.length; item++) {
        final centerX = size.width * (0.28 + item * 0.22);
        final itemHeight = blockHeight * (item == 1 ? 1.12 : 0.8);
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            centerX - blockWidth / 2,
            baseline - itemHeight,
            blockWidth,
            itemHeight,
          ),
          const Radius.circular(9),
        );
        canvas.drawRRect(rect, Paint()..color = colors[item]);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(rect.left, rect.top, rect.width, 7),
            const Radius.circular(9),
          ),
          Paint()..color = Colors.white.withValues(alpha: 0.18),
        );
      }

      canvas.drawLine(
        Offset(size.width * 0.08, baseline),
        Offset(size.width * 0.92, baseline),
        shelfPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ShelvesIllustrationPainter oldDelegate) =>
      false;
}
