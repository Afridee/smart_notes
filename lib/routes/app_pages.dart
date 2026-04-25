import 'package:get/get.dart';

import '../features/chat/chat_binding.dart';
import '../features/chat/views/chat_page.dart';
import '../features/notes/notes_binding.dart';
import '../features/notes/views/note_editor_page.dart';
import '../features/notes/views/notes_list_page.dart';
import '../features/setup/setup_binding.dart';
import '../features/setup/views/model_setup_page.dart';
import 'app_routes.dart';

abstract class AppPages {
  static final pages = <GetPage<dynamic>>[
    GetPage(
      name: AppRoutes.setup,
      page: () => const ModelSetupPage(),
      binding: SetupBinding(),
    ),
    GetPage(
      name: AppRoutes.notes,
      page: () => const NotesListPage(),
      binding: NotesBinding(),
    ),
    GetPage(
      name: AppRoutes.noteEditor,
      page: () => const NoteEditorPage(),
      binding: NotesBinding(),
    ),
    GetPage(
      name: AppRoutes.chat,
      page: () => const ChatPage(),
      binding: ChatBinding(),
    ),
  ];

  static const initial = AppRoutes.setup;
}
