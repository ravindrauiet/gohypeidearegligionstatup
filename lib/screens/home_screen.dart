import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/buddy_service.dart';
import '../widgets/buddy/buddy_badge_scope.dart';
import '../widgets/custom_bottom_nav.dart';
import 'tabs/home_tab.dart';
import 'tabs/chart_tab.dart';
import 'tabs/more_tab.dart';
import 'tabs/chat_tab.dart';
import 'buddy/buddy_hub_tab.dart';

class HomeScreen extends StatefulWidget {
  static final GlobalKey<HomeScreenState> globalKey = GlobalKey<HomeScreenState>();

  const HomeScreen({super.key});

  static void switchTab(BuildContext context, int index, {String? targetSection}) {
    final state = context.findAncestorStateOfType<HomeScreenState>() ?? globalKey.currentState;
    if (state != null) {
      if (targetSection != null) {
        MoreTab.targetSectionNotifier.value = targetSection;
      }
      state._onTabSelected(index);
    }
  }

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  static const int _tabCount = 5;

  int _currentIndex = 0;

  /// Tabs are built lazily on first visit (then kept alive by the
  /// IndexedStack) so opening the dashboard doesn't fire every tab's network
  /// requests at once.
  final Set<int> _visitedTabs = {0};

  void _onTabSelected(int index) {
    if (index < 0 || index >= _tabCount || index == _currentIndex) return;
    setState(() {
      _currentIndex = index;
      _visitedTabs.add(index);
    });
    // Opening the Buddy tab: bring the badge up to date (throttled).
    if (index == _buddyTab) context.read<BuddyService>().refreshBadge();
  }

  static const int _buddyTab = 4;

  Widget _buildTab(int index) {
    if (!_visitedTabs.contains(index)) return const SizedBox.shrink();
    switch (index) {
      case 0:
        return HomeTab(onNavigateTab: _onTabSelected);
      case 1:
        return const ChartTab();
      case 2:
        return const MoreTab();
      case 3:
        return const ChatTab();
      case 4:
      default:
        return const BuddyHubTab();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BuddyBadgeScope(
      child: PopScope(
        // Back from any other tab returns to the Home tab before exiting.
        canPop: _currentIndex == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _onTabSelected(0);
        },
        child: Scaffold(
          body: IndexedStack(
            index: _currentIndex,
            children: List.generate(_tabCount, _buildTab),
          ),
          bottomNavigationBar: Selector<BuddyService, int>(
            selector: (_, s) => s.badgeCount,
            builder: (_, buddyCount, __) => CustomBottomNav(
              currentIndex: _currentIndex,
              onTap: _onTabSelected,
              badges: {_buddyTab: buddyCount},
            ),
          ),
        ),
      ),
    );
  }
}
