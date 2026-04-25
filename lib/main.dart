import 'package:flutter/widgets.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  const hfToken =
      String.fromEnvironment('HUGGINGFACE_TOKEN', defaultValue: '');
  FlutterGemma.initialize(
    huggingFaceToken: hfToken.isNotEmpty ? hfToken : null,
  );

  runApp(const SmartNotesApp());
}
