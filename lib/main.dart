import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import 'pages/search_page.dart';
import 'pages/result_page.dart';
import 'pages/detail_page.dart';
import 'theme/app_theme.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Select env file: allow override via --dart-define=ENV_FILE=..., else
  // use .env in debug/dev and .env.production in release.
  const envFromDefine = String.fromEnvironment('ENV_FILE', defaultValue: '');
  final envFile = envFromDefine.isNotEmpty
      ? envFromDefine
      : (kReleaseMode ? ".env.production" : ".env");
  await dotenv.load(fileName: envFile);
  // Initialize Firebase for Firestore/Chat/others
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const YamaBiyoriApp());
}

class YamaBiyoriApp extends StatelessWidget {
  const YamaBiyoriApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "晴れたらいいね！山日和",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ja', 'JP'),
        Locale('en'),
      ],
      home: const SearchPage(),
      routes: {
        '/search': (_) => const SearchPage(),
        '/result': (_) => const DummyResultRoute(),
        '/detail': (_) => const DummyDetailRoute(),
      },
    );
  }
}

class DummyResultRoute extends StatelessWidget {
  const DummyResultRoute({super.key});

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;

    return ResultPage(
      departureLabel: args?['departureLabel'] ?? "未設定",
      departureLat: args?['departureLat'] ?? 0,
      departureLng: args?['departureLng'] ?? 0,
      selectedLevel: args?['selectedLevel'],
      selectedAccessTime: args?['selectedAccessTime'],
      selectedCourseTime: args?['selectedCourseTime'],
      selectedStyles: args?['selectedStyles'],
      selectedPurposes: args?['selectedPurposes'],
      selectedOptions: args?['selectedOptions'],
      selectedAccessMethods: args?['selectedAccessMethods'],
    );
  }
}

class DummyDetailRoute extends StatelessWidget {
  const DummyDetailRoute({super.key});

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;

    return DetailPage(
      mountain: args?['mountain'] ?? {},
      departureLabel: args?['departureLabel'] ?? "未設定",
    );
  }
}
