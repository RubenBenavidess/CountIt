import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/config/app_config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(CountItApp(config: AppConfig.fromEnvironment()));
}
