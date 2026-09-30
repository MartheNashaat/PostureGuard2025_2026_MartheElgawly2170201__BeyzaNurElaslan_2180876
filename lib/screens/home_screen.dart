import 'package:flutter/material.dart';
import '../models/feedback_variant.dart';
import '../models/session_summary.dart';
import '../services/database_service.dart';
import '../services/calibration_service.dart';
import '../services/variant_service.dart';
import '../services/participant_service.dart';
import '../services/upload_service.dart';
import 'dart:async';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with RouteAware {
  SessionSummary? _lastSession;
  bool _hasCalibration = false;
  bool _loaded = false;
  FeedbackVariant? _variant;
  String? _participantId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final session = await DatabaseService.getLatestSession();
    final calibration = await CalibrationService.load();
    final variant = await VariantService.get();
    final participantId = await ParticipantService.get();
    unawaited(UploadService.flush());
    if (mounted) {
      setState(() {
        _variant = variant;
        _participantId = participantId;
        _lastSession = session;
        _hasCalibration = calibration != null;
        _loaded = true;
      });
    }
  }

  @override
  void didPopNext() {
    // Reload when returning from another screen
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route observer for didPopNext
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      _routeObserver?.unsubscribe(this);
      _routeObserver?.subscribe(this, route);
    }
    // Also reload here for initial load and deep nav returns
    _loadData();
  }

  static RouteObserver<PageRoute>? _routeObserver;

  Future<void> _selectVariant(FeedbackVariant v) async {
    await VariantService.set(v);
    if (mounted) setState(() => _variant = v);
  }

  /// Opens calibration → session, but only once a feedback mode is chosen,
  /// so no session is recorded without one.
  Future<void> _startSession() async {
    if (_participantId == null) {
      await _showParticipantIdDialog();
      if (_participantId == null || !mounted) return;
    }
    if (_variant == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a feedback mode first')),
      );
      return;
    }
    Navigator.pushNamed(context, '/calibration');
  }

  /// ID entry. Pre-filled with this phone's saved ID, so the user only types
  /// one the first time or when they choose to change it.
  Future<void> _showParticipantIdDialog() async {
    final controller = TextEditingController(text: _participantId ?? '');
    final saved = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final text = controller.text;
          final normalized = ParticipantService.normalize(text);
          final badChars = ParticipantService.hasInvalidCharacters(text);
          return AlertDialog(
            title: const Text('Participant ID'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Enter your participant ID.'),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 20,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    hintText: 'e.g. AB12CD',
                    border: const OutlineInputBorder(),
                    helperText: ParticipantService.rule,
                    helperMaxLines: 2,
                    errorText: badChars
                        ? 'Letters and numbers only (no spaces or symbols).'
                        : null,
                    errorMaxLines: 2,
                    suffixIcon: normalized != null
                        ? const Icon(Icons.check_circle, color: Colors.teal)
                        : null,
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: normalized == null
                    ? null
                    : () => Navigator.pop(context, normalized),
                style: FilledButton.styleFrom(backgroundColor: Colors.teal),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    if (saved == null) return;
    final id = await ParticipantService.set(saved);
    if (id != null && mounted) setState(() => _participantId = id);
  }

  Widget _buildParticipantRow() {
    final id = _participantId;
    return InkWell(
      onTap: _showParticipantIdDialog,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(id == null ? Icons.badge_outlined : Icons.badge,
                size: 18, color: id == null ? Colors.orange : Colors.teal),
            const SizedBox(width: 8),
            Text(
              id ?? 'Enter participant ID',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: id == null ? 0 : 1,
                color: id == null ? Colors.orange : null,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.edit, size: 16, color: Colors.grey[500]),
          ],
        ),
      ),
    );
  }

  Widget _buildVariantSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Feedback when posture is bad',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[600])),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final v in FeedbackVariant.values) ...[
              if (v != FeedbackVariant.values.first) const SizedBox(width: 8),
              Expanded(child: _variantButton(v)),
            ],
          ],
        ),
      ],
    );
  }

  Widget _variantButton(FeedbackVariant v) {
    final selected = v == _variant;
    return OutlinedButton(
      onPressed: () => _selectVariant(v),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        backgroundColor: selected ? Colors.teal : null,
        foregroundColor: selected ? Colors.white : Colors.teal,
        side: const BorderSide(color: Colors.teal),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(v.icon, size: 28),
          const SizedBox(height: 6),
          Text(v.label, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _routeObserver?.unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Cache route observer
    _routeObserver ??= RouteObserver<PageRoute>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('PostureGuard'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const SizedBox(height: 16),
            const Icon(
              Icons.accessibility_new,
              size: 80,
              color: Colors.teal,
            ),
            const SizedBox(height: 20),
            const Text(
              'PostureGuard',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Monitor your posture in real time',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            if (_loaded) _buildParticipantRow(),

            const SizedBox(height: 32),

            // Last session card
            if (_loaded && _lastSession != null) ...[
              _buildLastSessionCard(),
              const SizedBox(height: 24),
            ],

            _buildVariantSelector(),
            const SizedBox(height: 16),

            // Start session button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _startSession,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('Start Session',
                    style: TextStyle(fontSize: 18)),
              ),
            ),

            // Recalibrate hint
            if (_loaded && _hasCalibration) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {
                  Navigator.pushNamed(context, '/calibration');
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Recalibrate'),
                style: TextButton.styleFrom(foregroundColor: Colors.grey[600]),
              ),
            ],

            const SizedBox(height: 12),

            // View history button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pushNamed(context, '/history');
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.teal,
                  side: const BorderSide(color: Colors.teal),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('View History',
                    style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLastSessionCard() {
    final s = _lastSession!;
    final scoreColor = s.goodPosturePercent >= 80
        ? Colors.green
        : s.goodPosturePercent >= 50
            ? Colors.orange
            : Colors.red;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text('Last Session',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600])),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Score circle
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: scoreColor, width: 4),
                ),
                child: Center(
                  child: Text(
                    '${s.goodPosturePercent.round()}%',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: scoreColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatDate(s.date),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Duration: ${s.formattedDuration}',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey[600]),
                    ),
                    Text(
                      'Best streak: ${_formatStreak(s.longestStreakSeconds)}',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '${months[date.month - 1]} ${date.day} at $hour:$minute';
  }

  String _formatStreak(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins}m ${secs}s';
  }
}
