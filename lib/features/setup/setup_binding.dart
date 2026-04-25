import 'package:get/get.dart';

import 'controllers/model_setup_controller.dart';

class SetupBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ModelSetupController>(() => ModelSetupController());
  }
}
