import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BarsApp());
}

/// Mude aqui conforme o dispositivo que estiver usando:
const String baseUrl = 'http://10.0.2.2:8000'; // Para o Emulador (ATIVO)
/// const String baseUrl = 'http://192.168.1.24:8000'; // Seu IP ATUAL
/// const String baseUrl = 'http://192.168.1.10:8000'; // IP Antigo

///  celular
///

class BarsApp extends StatelessWidget {
  const BarsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bares por Nota',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  double minRating = 4.0;
  int minReviews = 20;
  int radius = 3000;
  bool? openNow;
  String? query;

  final TextEditingController _radiusCtrl = TextEditingController(text: '3000');
  final TextEditingController _minReviewsCtrl =
      TextEditingController(text: '20');
  final TextEditingController _queryCtrl = TextEditingController();

  bool loading = false;
  List<dynamic> items = [];
  bool _inlineFiltersVisible = true;

  Future<Position> _getPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) throw Exception('Serviço de localização desativado');

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Permissão de localização negada');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception('Permissão de localização negada permanentemente');
    }
    return Geolocator.getCurrentPosition();
  }

  Future<void> _fetch() async {
    setState(() => loading = true);
    try {
      final pos = await _getPosition();
      final qp = {
        'lat': '${pos.latitude}',
        'lng': '${pos.longitude}',
        'radius': '$radius',
        'minRating': '$minRating',
        'minReviews': '$minReviews',
        if (openNow != null) 'openNow': '$openNow',
        if (query != null && query!.trim().length >= 2) 'query': query!.trim(),
      };
      final uri = Uri.parse('$baseUrl/api/bars').replace(queryParameters: qp);
      final resp = await http.get(uri);
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
      }
      final data = json.decode(resp.body) as Map<String, dynamic>;
      setState(() {
        items = (data['items'] as List?) ?? [];
        _inlineFiltersVisible = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _openMaps(String? url) async {
    if (url == null || url.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link do Maps indisponível')),
      );
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('URL inválida: $url')),
      );
      return;
    }

    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      try {
        await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível abrir o Maps: $e')),
        );
      }
    }
  }

  Future<void> _openUber(double? lat, double? lng, String? name) async {
    if (lat == null || lng == null) return;
    final encodedName = Uri.encodeComponent(name ?? "Destino");
    final deepLink =
        "uber://?action=setPickup&pickup=my_location&dropoff[latitude]=$lat&dropoff[longitude]=$lng&dropoff[nickname]=$encodedName";
    final webFallback =
        "https://m.uber.com/ul/?action=setPickup&pickup=my_location&dropoff[latitude]=$lat&dropoff[longitude]=$lng&dropoff[nickname]=$encodedName";

    final uri = Uri.parse(deepLink);
    final fallbackUri = Uri.parse(webFallback);

    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
    }
  }

  // filtros inline
  Widget _inlineFilters() {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queryCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Buscar por nome/bairro (opcional)',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => query = v,
                    onSubmitted: (_) => _fetch(),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: loading ? null : _fetch,
                  icon: loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.search),
                  label: const Text('Buscar'),
                )
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 240,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Nota mínima: ${minRating.toStringAsFixed(1)}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Slider(
                        value: minRating,
                        min: 0,
                        max: 5,
                        divisions: 50,
                        onChanged: (v) => setState(() =>
                            minRating = double.parse(v.toStringAsFixed(1))),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: TextField(
                    controller: _minReviewsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Mín. avaliações',
                      prefixIcon: Icon(Icons.reviews),
                      hintText: '20',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) =>
                        setState(() => minReviews = int.tryParse(v) ?? 20),
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: _radiusCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Raio (m)',
                      prefixIcon: Icon(Icons.radar),
                      hintText: '3000',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) =>
                        setState(() => radius = int.tryParse(v) ?? 3000),
                  ),
                ),
                SegmentedButton<bool?>(
                  segments: const [
                    ButtonSegment(value: null, label: Text('Todos')),
                    ButtonSegment(value: true, label: Text('Abertos')),
                    ButtonSegment(value: false, label: Text('Fechados')),
                  ],
                  selected: {openNow},
                  onSelectionChanged: (s) => setState(() => openNow = s.first),
                  style: ButtonStyle(
                    backgroundColor: WidgetStatePropertyAll(
                        cs.surfaceVariant.withOpacity(.3)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openFiltersSheet() {
    _radiusCtrl.text = radius.toString();
    _minReviewsCtrl.text = minReviews.toString();
    _queryCtrl.text = (query ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        double tmpMinRating = minRating;
        bool? tmpOpen = openNow;

        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: StatefulBuilder(
            builder: (context, setSheet) {
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Filtros',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _queryCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Busca (nome/bairro) - opcional',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Nota mínima: ${tmpMinRating.toStringAsFixed(1)}'),
                    Slider(
                      value: tmpMinRating,
                      min: 0,
                      max: 5,
                      divisions: 50,
                      onChanged: (v) => setSheet(() =>
                          tmpMinRating = double.parse(v.toStringAsFixed(1))),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _minReviewsCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Mínimo de avaliações',
                        prefixIcon: Icon(Icons.reviews),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _radiusCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Raio (m)',
                        prefixIcon: Icon(Icons.radar),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<bool?>(
                      segments: const [
                        ButtonSegment(value: null, label: Text('Todos')),
                        ButtonSegment(value: true, label: Text('Abertos')),
                        ButtonSegment(value: false, label: Text('Fechados')),
                      ],
                      selected: {tmpOpen},
                      onSelectionChanged: (s) =>
                          setSheet(() => tmpOpen = s.first),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        OutlinedButton(
                          onPressed: () {
                            setState(() {
                              minRating = 4.0;
                              minReviews = 20;
                              radius = 3000;
                              openNow = null;
                              query = null;
                              _minReviewsCtrl.text = '20';
                              _radiusCtrl.text = '3000';
                              _queryCtrl.clear();
                            });
                            Navigator.pop(ctx);
                            _fetch();
                          },
                          child: const Text('Limpar'),
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: () {
                            setState(() {
                              minRating = tmpMinRating;
                              minReviews =
                                  int.tryParse(_minReviewsCtrl.text) ?? 20;
                              radius = int.tryParse(_radiusCtrl.text) ?? 3000;
                              openNow = tmpOpen;
                              query = _queryCtrl.text.trim().isEmpty
                                  ? null
                                  : _queryCtrl.text.trim();
                            });
                            Navigator.pop(ctx);
                            _fetch();
                          },
                          icon: const Icon(Icons.check),
                          label: const Text('Aplicar'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  String _priceLabel(dynamic v) {
    const map = {0: 'Grátis', 1: 'Barato', 2: 'Moderado', 3: 'Caro', 4: 'Luxo'};
    return map[v] ?? '—';
  }

  String _reviewsLabel(num n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)} mil';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/icon.png', height: 32),
            const SizedBox(width: 8),
            Text(
              'Find me a Bar',
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.w800,
                fontSize: 22,
                letterSpacing: -0.5,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Filtros',
            onPressed: _inlineFiltersVisible ? null : _openFiltersSheet,
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: loading ? null : _fetch,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (_inlineFiltersVisible) _inlineFilters(),
          if (items.isEmpty && !_inlineFiltersVisible)
            Padding(
              padding: const EdgeInsets.only(top: 80),
              child: Center(
                child: Text('Nenhum bar encontrado',
                    style: TextStyle(color: cs.outline)),
              ),
            ),
          ...items.map((raw) {
            final it = raw as Map<String, dynamic>;
            final name = (it['name'] ?? '(sem nome)').toString();
            final rating = (it['rating'] ?? 0).toString();
            final reviews = (it['userRatingsTotal'] ?? 0) as num;
            final price = it['priceLevel'];
            final photo = it['photoUri']?.toString();
            final mapsUrl = it['mapsUrl']?.toString();
            final open = it['openNow'] == true;

            // Ajuste para fotos com caminho relativo e limpeza de caracteres invisíveis (\n, espaços)
            String? fullPhotoPath = photo?.replaceAll(RegExp(r'\s+'), '');
            if (fullPhotoPath != null && fullPhotoPath.startsWith('/')) {
              fullPhotoPath = '$baseUrl$fullPhotoPath';
            }

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Material(
                elevation: 1,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: mapsUrl == null ? null : () => _openMaps(mapsUrl),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (fullPhotoPath != null)
                        ClipRRect(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(16),
                            bottomLeft: Radius.circular(16),
                          ),
                          child: Image.network(
                            fullPhotoPath,
                            width: 120,
                            height: 120,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              debugPrint('Erro ao carregar imagem: $error');
                              return Container(
                                width: 120,
                                height: 120,
                                color: cs.surfaceVariant,
                                child: const Icon(Icons.image_not_supported),
                              );
                            },
                          ),
                        )
                      else
                        Container(
                          width: 120,
                          height: 120,
                          color: cs.surfaceVariant,
                          child: const Icon(Icons.local_bar),
                        ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: cs.primaryContainer,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.star, size: 16),
                                        const SizedBox(width: 4),
                                        Text(rating,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.reviews, size: 16),
                                  const SizedBox(width: 4),
                                  Text('${_reviewsLabel(reviews)} avaliações'),
                                  const SizedBox(width: 12),
                                  const Icon(Icons.payments, size: 16),
                                  const SizedBox(width: 4),
                                  Text(_priceLabel(price)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  if (open)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(.14),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color:
                                                Colors.green.withOpacity(.4)),
                                      ),
                                      child: const Text('Aberto',
                                          style:
                                              TextStyle(color: Colors.green)),
                                    ),
                                  const Spacer(),

                                  // Botão Uber (usa latitude/longitude vindas do backend)
                                  IconButton(
                                    onPressed:
                                        (it['location']?['lat'] != null &&
                                                it['location']?['lng'] != null)
                                            ? () => _openUber(
                                                  (it['location']['lat'] as num)
                                                      .toDouble(),
                                                  (it['location']['lng'] as num)
                                                      .toDouble(),
                                                  name,
                                                )
                                            : null,
                                    icon: Image.asset('assets/uber_icon.png',
                                        width: 24, height: 24),
                                    tooltip: 'Ir com Uber',
                                  ),

                                  // Botão Maps
                                  IconButton(
                                    onPressed: mapsUrl == null
                                        ? null
                                        : () => _openMaps(mapsUrl),
                                    icon: const Icon(Icons.map),
                                    tooltip: 'Abrir no Maps',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
      floatingActionButton: _inlineFiltersVisible
          ? null
          : FloatingActionButton.extended(
              onPressed: loading ? null : _fetch,
              icon: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.search),
              label: const Text('Buscar'),
            ),
    );
  }
}
