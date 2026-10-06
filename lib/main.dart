import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'db.dart';
import 'notifications.dart';
import 'prefs.dart';
import 'screens/entry_edit.dart';
import 'screens/report.dart';
import 'screens/settings.dart';
import 'screens/stats.dart';
import 'screens/today.dart';
import 'screens/weight.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'pl_PL';
  await initializeDateFormatting('pl_PL');
  await Db.init();
  await Prefs.load();
  await Notifications.init();
  Db.onChanged = Notifications.reschedule; // każda zmiana danych planuje powiadomienia od nowa
  runApp(const FoodDiaryApp());
  await Notifications.askPermissionOnce();
  await Notifications.reschedule();
}

class FoodDiaryApp extends StatelessWidget {
  const FoodDiaryApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Dzienniczek',
        debugShowCheckedModeBanner: false,
        theme: appTheme,
        locale: const Locale('pl', 'PL'),
        supportedLocales: const [Locale('pl', 'PL')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const HomeShell(),
      );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;
  Key _tabKey = UniqueKey(); // nowy klucz = świeże dane zakładki

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    notifTap.addListener(_onNotifTap);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onNotifTap()); // start z powiadomienia
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    notifTap.removeListener(_onNotifTap);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Notifications.reschedule();
      setState(() => _tabKey = UniqueKey()); // np. po północy "Dziś" ma pokazać nowy dzień
    }
  }

  void _onNotifTap() {
    final p = notifTap.value;
    if (p == null) return;
    notifTap.value = null;
    setState(() => (_tab = p == 'weight' ? 1 : 0, _tabKey = UniqueKey()));
    if (p == 'add_meal') {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const EntryEditScreen()))
          .then((_) => setState(() => _tabKey = UniqueKey()));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        // ponytail: zakładki budowane na nowo przy przełączeniu, dzięki czemu dane zawsze świeże
        body: SafeArea(
          child: switch (_tab) {
            0 => TodayScreen(key: _tabKey),
            1 => WeightScreen(key: _tabKey),
            2 => StatsScreen(key: _tabKey),
            3 => ReportScreen(key: _tabKey),
            _ => SettingsScreen(key: _tabKey),
          },
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.restaurant_outlined), selectedIcon: Icon(Icons.restaurant), label: 'Dziś'),
            NavigationDestination(
                icon: Icon(Icons.monitor_weight_outlined), selectedIcon: Icon(Icons.monitor_weight), label: 'Waga'),
            NavigationDestination(
                icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Statystyki'),
            NavigationDestination(
                icon: Icon(Icons.description_outlined), selectedIcon: Icon(Icons.description), label: 'Raport'),
            NavigationDestination(
                icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Ustawienia'),
          ],
        ),
      );
}
