import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'app.dart';
import 'core/config/env.dart';
import 'core/theme/kora_colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppEnv.validate();
  await Future.wait([
    initializeDateFormatting('ru'),
    initializeDateFormatting('en'),
    initializeDateFormatting('kk'),
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: KoraColors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const ProviderScope(child: KoraApp()));
}
