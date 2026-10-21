import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/domain/telefono.dart';
import '../../../shared/domain/valor_invalido.dart';
import '../../../shared/presentation/tema/colores.dart';
import '../../../shared/presentation/tema/tema.dart';
import '../application/clientes.dart';
import '../domain/cliente.dart';

/// Cómo se cerró la hoja.
sealed class ResultadoHojaCliente {
  const ResultadoHojaCliente(this.cliente);

  final Cliente cliente;
}

/// Se creó o se editó [cliente].
class ClienteGuardado extends ResultadoHojaCliente {
  const ClienteGuardado(super.cliente, {required this.nuevo});

  final bool nuevo;
}

/// Ante el aviso de teléfono repetido, el usuario eligió el cliente que ya
/// existía en vez de guardar: no se escribió nada.
class ClienteExistenteElegido extends ResultadoHojaCliente {
  const ClienteExistenteElegido(super.cliente);
}

/// Alta y edición de un cliente (PRD módulo 1): nombre y, opcional, celular
/// peruano de 9 dígitos; "Número de otro país" cambia el campo al número
/// completo con código de país. Devuelve el cliente, para que Crear Encargo
/// (Sprint 2) la use para crear uno sin salir del flujo.
class HojaCliente extends ConsumerStatefulWidget {
  const HojaCliente({super.key, this.cliente, this.nombreInicial = '', this.telefonoInicial = ''});

  /// `null` = cliente nuevo.
  final Cliente? cliente;

  /// Prellenado desde una búsqueda sin resultados (PRD: "Crear cliente nuevo"
  /// con el texto buscado).
  final String nombreInicial;
  final String telefonoInicial;

  static Future<ResultadoHojaCliente?> abrir(
    BuildContext context, {
    Cliente? cliente,
    String nombreInicial = '',
    String telefonoInicial = '',
  }) => showModalBottomSheet<ResultadoHojaCliente>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => HojaCliente(
      cliente: cliente,
      nombreInicial: nombreInicial,
      telefonoInicial: telefonoInicial,
    ),
  );

  @override
  ConsumerState<HojaCliente> createState() => _EstadoHojaCliente();
}

class _EstadoHojaCliente extends ConsumerState<HojaCliente> {
  late final TextEditingController _nombre;
  late final TextEditingController _telefono;
  late bool _internacional;
  String? _errorNombre;
  String? _errorTelefono;
  bool _guardando = false;

  /// El cliente que ya tiene el teléfono escrito; mientras se muestra el
  /// aviso, "Guardar" pasa a "Guardar igual".
  Cliente? _repetido;
  Telefono? _telefonoAvisado;

  @override
  void initState() {
    super.initState();
    final cliente = widget.cliente;
    final telefono = cliente?.telefono;
    _nombre = TextEditingController(text: cliente?.nombre ?? widget.nombreInicial);
    if (cliente != null) {
      _internacional = telefono != null && !telefono.esPeruano;
      _telefono = TextEditingController(text: telefono?.formatear() ?? '');
    } else {
      _internacional = widget.telefonoInicial.trim().startsWith('+');
      _telefono = TextEditingController(text: widget.telefonoInicial.trim());
    }
  }

  @override
  void dispose() {
    _nombre.dispose();
    _telefono.dispose();
    super.dispose();
  }

  void _cambiarModo() => setState(() {
    _internacional = !_internacional;
    _errorTelefono = null;
    _repetido = null;
  });

  Future<void> _guardar() async {
    if (_guardando) return;
    String? nombre;
    Telefono? telefono;
    String? errorNombre;
    String? errorTelefono;
    try {
      nombre = Cliente.validarNombre(_nombre.text);
    } on ValorInvalido catch (error) {
      errorNombre = error.mensaje;
    }
    try {
      telefono = Cliente.leerTelefono(_telefono.text, internacional: _internacional);
    } on ValorInvalido catch (error) {
      errorTelefono = error.mensaje;
    }
    setState(() {
      _errorNombre = errorNombre;
      _errorTelefono = errorTelefono;
    });
    if (nombre == null || errorTelefono != null) return;

    setState(() => _guardando = true);
    try {
      final repositorio = ref.read(repositorioClientesProvider);
      final actual = widget.cliente;
      // Aviso de teléfono repetido (decisión del usuario): no bloquea. Se
      // muestra una vez por número; un segundo toque guarda igual.
      if (telefono != null && telefono != actual?.telefono && telefono != _telefonoAvisado) {
        final otros = await repositorio.conTelefono(telefono, excepto: actual?.id);
        if (otros.isNotEmpty) {
          setState(() {
            _repetido = otros.first;
            _telefonoAvisado = telefono;
          });
          return;
        }
      }
      final guardado = actual == null
          ? await repositorio.crear(nombre: nombre, telefono: telefono)
          : await repositorio.editar(actual, nombre: nombre, telefono: telefono);
      if (mounted) Navigator.pop(context, ClienteGuardado(guardado, nuevo: actual == null));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final repetido = _repetido;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Medidas.espacio,
        0,
        Medidas.espacio,
        Medidas.espacio + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.cliente == null ? 'Nuevo cliente' : 'Editar cliente',
              style: tema.textTheme.titleLarge,
            ),
            const SizedBox(height: Medidas.espacio),
            TextField(
              controller: _nombre,
              autofocus: widget.nombreInicial.isEmpty && widget.cliente == null,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(labelText: 'Nombre', errorText: _errorNombre),
            ),
            const SizedBox(height: Medidas.espacio),
            TextField(
              key: ValueKey(_internacional),
              controller: _telefono,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(_internacional ? r'[0-9+ \-]' : r'[0-9 \-]'),
                ),
              ],
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                if (_repetido != null) setState(() => _repetido = null);
              },
              onSubmitted: (_) => _guardar(),
              decoration: InputDecoration(
                labelText: _internacional
                    ? 'Teléfono con código de país (opcional)'
                    : 'Celular (opcional)',
                hintText: _internacional ? '+34 612 345 678' : '987 654 321',
                // El "+51" se ve pero no se escribe (PRD módulo 1).
                prefixText: _internacional ? null : '+51 ',
                errorText: _errorTelefono,
                errorMaxLines: 2,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _cambiarModo,
                child: Text(_internacional ? 'Usar celular de Perú' : 'Número de otro país'),
              ),
            ),
            if (repetido != null) ...[
              _AvisoRepetido(
                cliente: repetido,
                alElegir: () => Navigator.pop(context, ClienteExistenteElegido(repetido)),
              ),
              const SizedBox(height: Medidas.espacio),
            ],
            FilledButton(
              onPressed: _guardando ? null : _guardar,
              child: Text(repetido == null ? 'Guardar' : 'Guardar igual'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvisoRepetido extends StatelessWidget {
  const _AvisoRepetido({required this.cliente, required this.alElegir});

  final Cliente cliente;
  final VoidCallback alElegir;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colores.ambarFondo,
        borderRadius: BorderRadius.circular(Medidas.radio),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Ya tienes a ${cliente.nombre} con este número.'),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: alElegir, child: Text('Ver a ${cliente.nombre}')),
          ],
        ),
      ),
    );
  }
}
