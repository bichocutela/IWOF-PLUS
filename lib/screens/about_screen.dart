import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_updates.dart';

const aboutPink = Color(0xFFD93F8F);
const aboutMuted = Color(0xFF64748B);

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  final AppUpdates updates = AppUpdates();
  StreamSubscription<dynamic>? progressSubscription;
  InstalledVersion? installed;
  AvailableRelease? latest;
  String message = 'Consultando versão instalada...';
  bool checking = false;
  bool downloading = false;
  int progress = 0;

  @override
  void initState() {
    super.initState();
    progressSubscription = AppUpdates.downloadProgress
        .receiveBroadcastStream()
        .listen((event) {
      if (mounted && event is int) {
        setState(() => progress = event);
      }
    });
    unawaited(check());
  }

  @override
  void dispose() {
    unawaited(progressSubscription?.cancel());
    updates.close();
    super.dispose();
  }

  Future<void> check() async {
    if (checking || downloading) return;
    setState(() {
      checking = true;
      message = 'Verificando atualizações...';
    });
    try {
      final current = await updates.installedVersion();
      final release = await updates.latestRelease();
      if (!mounted) return;
      setState(() {
        installed = current;
        latest = release;
        message = release == null
            ? 'Ainda não existe uma release publicada.'
            : AppUpdates.compareVersions(release.version, current.name) > 0
                ? 'Nova versão ${release.version} disponível.'
                : 'Você já está na versão mais recente.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        message = '$error'.replaceFirst('Exception: ', '');
        latest = null;
      });
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  Future<void> install() async {
    final release = latest;
    if (release == null || downloading) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Atualizar IWOF PLUS?'),
        content: Text(
          'Baixar a versão ${release.version} e abrir o instalador do Android? '
          'Você precisará confirmar a instalação no aparelho. '
          'A atualização conserva os dados quando a assinatura é a mesma.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Baixar e instalar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      downloading = true;
      progress = 0;
      message = 'Baixando e verificando o APK...';
    });
    try {
      await updates.install(release);
      if (!mounted) return;
      setState(() {
        message = 'Download verificado. Confirme a atualização no Android.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => message = '$error'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => downloading = false);
    }
  }

  Future<void> openReleases() async {
    await launchUrl(
      Uri.parse(releasesUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final canInstall = installed != null &&
        latest != null &&
        AppUpdates.compareVersions(latest!.version, installed!.name) > 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Sobre o IWOF PLUS')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.system_update_alt_rounded,
              size: 52, color: aboutPink),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              'IWOF PLUS',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 6),
          const Center(
            child: Text('Atualizações do aplicativo',
                style: TextStyle(color: aboutMuted)),
          ),
          const SizedBox(height: 24),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.phone_android_rounded,
                      color: aboutPink),
                  title: const Text('Versão instalada'),
                  subtitle: Text(installed == null
                      ? 'Carregando...'
                      : '${installed!.name} (código ${installed!.code})'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.new_releases_outlined,
                      color: aboutPink),
                  title: const Text('Última versão publicada'),
                  subtitle: Text(latest?.version ?? 'Não disponível'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(message,
                  style: const TextStyle(color: aboutMuted, height: 1.5)),
            ),
          ),
          if (downloading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  LinearProgressIndicator(
                    value: progress > 0 ? progress / 100 : null,
                  ),
                  const SizedBox(height: 8),
                  Text(progress > 0
                      ? 'Download: $progress%'
                      : 'Preparando download...'),
                ],
              ),
            ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: checking || downloading ? null : check,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(checking ? 'Verificando...' : 'Verificar atualizações'),
          ),
          if (canInstall) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: downloading ? null : install,
              icon: const Icon(Icons.download_rounded),
              label: const Text('Atualizar agora'),
            ),
          ],
          const SizedBox(height: 14),
          TextButton.icon(
            onPressed: openReleases,
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Ver versões no GitHub'),
          ),
          const SizedBox(height: 14),
          const Text(
            'As atualizações são verificadas no GitHub oficial. '
            'O APK é conferido por SHA-256 e instalado pelo sistema Android. '
            'Para atualizar por cima é indispensável a mesma assinatura '
            'da versão anteriormente instalada.',
            textAlign: TextAlign.center,
            style: TextStyle(color: aboutMuted, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }
}
