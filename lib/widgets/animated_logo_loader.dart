import 'package:flutter/material.dart';

class AnimatedLogoLoader extends StatelessWidget {
  final double size;
  final Color? color;
  
  const AnimatedLogoLoader({
    Key? key,
    this.size = 50.0,
    this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final primaryColor = color ?? Theme.of(context).primaryColor;
    
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        color: primaryColor,
        strokeWidth: size > 30 ? 3.0 : 2.0,
      ),
    );
  }
}
