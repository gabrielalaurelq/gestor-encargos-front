import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'features/sesion/application/sesion.dart';
import 'shared/infrastructure/firebase.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final firebase = await iniciarFirebase();
  runApp(
    ProviderScope(
      overrides: [firebaseListoProvider.overrideWithValue(firebase)],
      child: const GestorEncargosApp(),
    ),
  );
}
