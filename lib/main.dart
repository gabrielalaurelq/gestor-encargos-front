import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'demo/modo_demo.dart';
import 'features/sesion/application/sesion.dart';
import 'shared/infrastructure/firebase.dart';
import 'shared/infrastructure/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (modoDemo) {
    final contenedor = ProviderContainer(overrides: overridesDemo());
    await prepararDemo(contenedor.read(baseDatosProvider));
    runApp(UncontrolledProviderScope(container: contenedor, child: const GestorEncargosApp()));
    return;
  }
  final firebase = await iniciarFirebase();
  runApp(
    ProviderScope(
      overrides: [firebaseListoProvider.overrideWithValue(firebase)],
      child: const GestorEncargosApp(),
    ),
  );
}
