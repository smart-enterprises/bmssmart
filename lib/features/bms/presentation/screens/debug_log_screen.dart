// lib/features/bms/presentation/screens/debug_log_screen.dart
//
// On-screen log viewer. Subscribes to AppLogger's stream and renders entries
// with color-coded levels. Includes copy-all and clear buttons.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/theme/app_theme.dart';

class DebugLogScreen extends StatefulWidget {
  const DebugLogScreen({super.key});

  @override
  State<DebugLogScreen> createState() => _DebugLogScreenState();
}

class _DebugLogScreenState extends State<DebugLogScreen> {
  late List<LogEntry> _entries;
  StreamSubscription<LogEntry>? _sub;
  final ScrollController _scroll = ScrollController();
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    _entries = AppLogger.instance.entries;
    _sub = AppLogger.instance.stream.listen((entry) {
      if (!mounted) return;
      setState(() => _entries = AppLogger.instance.entries);
      if (_autoScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.animateTo(
              _scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _copyAll() async {
    final text = AppLogger.instance.dumpAll();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${_entries.length} log lines copied to clipboard'), duration: const Duration(seconds: 2)),
    );
  }

  void _clear() {
    AppLogger.instance.clear();
  }

  Color _colorFor(LogLevel level) => switch (level) {
        LogLevel.info => AppColors.textSec,
        LogLevel.warn => const Color(0xFFD29922),
        LogLevel.error => AppColors.danger,
        LogLevel.success => AppColors.success,
        LogLevel.debug => const Color(0xFF3B82F6),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: appBackgroundGradient),
        child: Stack(
          children: [
            const AmbientBackground(),
            SafeArea(
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(child: _entries.isEmpty ? _buildEmpty() : _buildList()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.textSec), onPressed: () => Navigator.of(context).pop()),
          const Text('Debug Log', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 18)),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: AppColors.chipBg, borderRadius: BorderRadius.circular(10)),
            child: Text('${_entries.length}', style: const TextStyle(color: AppColors.textSec, fontSize: 12)),
          ),
          const Spacer(),
          IconButton(
            tooltip: _autoScroll ? 'Disable auto-scroll' : 'Enable auto-scroll',
            icon: Icon(
              _autoScroll ? Icons.vertical_align_bottom : Icons.vertical_align_center,
              color: _autoScroll ? AppColors.primary : AppColors.textSec,
            ),
            onPressed: () => setState(() => _autoScroll = !_autoScroll),
          ),
          IconButton(tooltip: 'Copy all', icon: const Icon(Icons.copy_all, color: AppColors.textSec), onPressed: _copyAll),
          IconButton(tooltip: 'Clear', icon: const Icon(Icons.delete_outline, color: AppColors.textSec), onPressed: _clear),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Text(
        'No log entries yet.\nTry connecting to a device.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textSec, fontSize: 14),
      ),
    );
  }

  Widget _buildList() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GlassCard(
        radius: 16,
        padding: EdgeInsets.zero,
        child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: _entries.length,
          itemBuilder: (context, i) {
            final entry = _entries[i];
            final color = _colorFor(entry.level);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: color, width: 3), bottom: const BorderSide(color: AppColors.trackBg, width: 1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(entry.formattedTime, style: const TextStyle(color: AppColors.textTertiary, fontSize: 11, fontFamily: 'monospace')),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                        child: Text(
                          entry.levelLabel.trim(),
                          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700, fontFamily: 'monospace'),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          entry.tag,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textSec, fontSize: 11, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  SelectableText(
                    entry.message,
                    style: const TextStyle(color: AppColors.text, fontSize: 12.5, fontFamily: 'monospace', height: 1.35),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
