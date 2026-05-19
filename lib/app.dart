import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'bindings/initial_bindings.dart';
import 'routes/app_pages.dart';
import 'theme/app_theme.dart';

class SmartNotesApp extends StatelessWidget {
  const SmartNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Smart Notes',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      initialBinding: InitialBindings(),
      initialRoute: AppPages.initial,
      getPages: AppPages.pages,
    );
  }
}
