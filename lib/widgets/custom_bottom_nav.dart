import 'package:flutter/material.dart';

class CustomBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const CustomBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      decoration: BoxDecoration(
        color: const Color(0xFFFCF7F1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
        border: Border(
          top: BorderSide(
            color: Colors.grey.withOpacity(0.2),
            width: 0.8,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(0, 'Home', _buildHomeIcon(currentIndex == 0)),
          _buildNavItem(1, 'Chart', _buildChartIcon(currentIndex == 1)),
          _buildNavItem(2, 'More', _buildMoreIcon(currentIndex == 2)),
          _buildNavItem(3, 'Chat', _buildChatIcon(currentIndex == 3)),
          _buildNavItem(4, 'Love', _buildLoveIcon(currentIndex == 4)),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, String label, Widget iconWidget) {
    final isSelected = currentIndex == index;
    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 60,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: isSelected
                    ? Border.all(color: Colors.black, width: 2)
                    : Border.all(color: Colors.transparent, width: 2),
              ),
              child: iconWidget,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.black : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeIcon(bool active) {
    return Icon(
      Icons.adjust_rounded,
      size: 22,
      color: active ? Colors.black : Colors.grey.shade700,
    );
  }

  Widget _buildChartIcon(bool active) {
    return Icon(
      Icons.pie_chart_outline_rounded,
      size: 22,
      color: active ? Colors.black : Colors.grey.shade700,
    );
  }

  Widget _buildMoreIcon(bool active) {
    return Icon(
      Icons.keyboard_double_arrow_up_rounded,
      size: 22,
      color: active ? Colors.black : Colors.grey.shade700,
    );
  }

  Widget _buildChatIcon(bool active) {
    return Icon(
      Icons.chat_bubble_outline_rounded,
      size: 22,
      color: active ? Colors.black : Colors.grey.shade700,
    );
  }

  Widget _buildLoveIcon(bool active) {
    return Icon(
      active ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      size: 22,
      color: active ? Colors.black : Colors.grey.shade700,
    );
  }
}
