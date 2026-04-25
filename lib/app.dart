import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'bindings/initial_bindings.dart';
import 'routes/app_pages.dart';

class SmartNotesApp extends StatelessWidget {
  const SmartNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Smart Notes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.indigo,
      ),
      initialBinding: InitialBindings(),
      initialRoute: AppPages.initial,
      getPages: AppPages.pages,
    );
  }
}
