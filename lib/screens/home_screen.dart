import 'package:flutter/material.dart';
import '../widgets/custom_bottom_nav.dart';
import 'tabs/home_tab.dart';
import 'tabs/chart_tab.dart';
import 'tabs/more_tab.dart';
import 'tabs/chat_tab.dart';
import 'tabs/love_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  void _onTabSelected(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> tabs = [
      HomeTab(onNavigateTab: _onTabSelected),
      const ChartTab(),
      const MoreTab(),
      const ChatTab(),
      const LoveTab(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: tabs,
      ),
      bottomNavigationBar: CustomBottomNav(
        currentIndex: _currentIndex,
        onTap: _onTabSelected,
      ),
    );
  }
}