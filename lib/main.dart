import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/onboarding_screen.dart';
import 'screens/birth_details_screen.dart';
import 'screens/home_screen.dart';
import 'screens/kundli_view_screen.dart';
import 'screens/chatbot_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'services/backend_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AstroApp());
}

class AstroApp extends StatelessWidget {
  const AstroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BackendService()),
      ],
      child: MaterialApp(
        title: 'AstroAI - Vedic Kundli & Guidance',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Roboto',
          primaryColor: Colors.black,
          scaffoldBackgroundColor: const Color(0xFFFCF7F1),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFFB9548),
            primary: Colors.black,
            secondary: const Color(0xFFFB9548),
            surface: const Color(0xFFFCF7F1),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
        ),
        initialRoute: '/onboarding',
        routes: {
          '/onboarding': (context) => const OnboardingScreen(),
          '/birth-details': (context) => const BirthDetailsScreen(),
          '/home': (context) => const HomeScreen(),
          '/kundli-view': (context) => const KundliViewScreen(),
          '/chatbot': (context) => const ChatbotScreen(),
          '/login': (context) => const LoginScreen(),
          '/register': (context) => const RegisterScreen(),
        },
      ),
    );
  }
}
