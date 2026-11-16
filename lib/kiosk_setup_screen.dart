import 'package:flutter/material.dart';

import 'kiosk_permissions.dart';

class KioskSetupScreen extends StatefulWidget {
  const KioskSetupScreen({
    required this.permissionService,
    required this.kioskLive,
    required this.preflight,
    required this.onGoLive,
    required this.onExitKiosk,
    required this.diagnostics,
    super.key,
  });

  final KioskPermissionService permissionService;
  final bool kioskLive;
  final Future<Map<String, bool>> Function() preflight;
  final Future<void> Function() onGoLive;
  final Future<void> Function() onExitKiosk;
  final Map<String, String> diagnostics;

  @override
  State<KioskSetupScreen> createState() => _KioskSetupScreenState();
}

class _KioskSetupScreenState extends State<KioskSetupScreen> {
  KioskPermissionSnapshot? _snapshot;
  Map<String, bool> _checks = const {};
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final snapshot = await widget.permissionService.refresh();
      final checks = await widget.preflight();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _checks = checks;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not refresh diagnostics: $error');
      }
    }
  }

  Future<void> _requestPermissions() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final snapshot = await widget.permissionService.requestDuringSetup(
        setupMode: true,
        kioskLive: widget.kioskLive,
      );
      final checks = await widget.preflight();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _checks = checks;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'Permission setup failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSettings() async {
    final opened = await widget.permissionService.openSettings();
    if (!opened && mounted) {
      setState(() => _error = 'Could not open app settings on this device.');
    }
  }

  Future<void> _goLive() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final snapshot = await widget.permissionService.refresh();
      final checks = await widget.preflight();
      if (!snapshot.criticalPermissionsGranted ||
          checks['Camera working'] != true ||
          checks['Storage writable'] != true) {
        if (mounted) {
          setState(() {
            _snapshot = snapshot;
            _checks = checks;
            _error =
                'Grant critical access and pass the camera/storage checks '
                'before enabling the booth.';
          });
        }
        return;
      }
      await widget.onGoLive();
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not enable kiosk mode: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _stateLabel(KioskPermissionState? state) => switch (state) {
    KioskPermissionState.granted => 'Granted',
    KioskPermissionState.limited => 'Limited (allowed)',
    KioskPermissionState.denied => 'Denied',
    KioskPermissionState.permanentlyDenied => 'Blocked — open settings',
    KioskPermissionState.notDetermined => 'Not requested',
    KioskPermissionState.notRequired => 'Not required',
    null => 'Checking…',
  };

  @override
  Widget build(BuildContext context) {
    final states =
        _snapshot?.states ?? const <KioskPermissionId, KioskPermissionState>{};
    return Dialog.fullscreen(
      backgroundColor: const Color(0xFFF8FAFC),
      child: SafeArea(
        child: Column(
          children: [
            AppBar(
              title: const Text('Operator setup & diagnostics'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text(
                    'Permissions are requested only in this admin setup screen. '
                    'Guests will not see system permission prompts.',
                  ),
                  const SizedBox(height: 12),
                  for (final config in kioskPermissions)
                    Card(
                      child: ListTile(
                        title: Text(
                          '${config.feature} · ${config.importance.name}',
                        ),
                        subtitle: Text(
                          '${config.rationale}\n${_stateLabel(states[config.id])}'
                          '${config.id == KioskPermissionId.bluetooth ? ' — ${config.fallback}' : ''}',
                        ),
                        isThreeLine: true,
                        trailing:
                            !widget.kioskLive &&
                                states[config.id] ==
                                    KioskPermissionState.permanentlyDenied
                            ? TextButton(
                                onPressed: _busy ? null : _openSettings,
                                child: const Text('Settings'),
                              )
                            : Icon(
                                states[config.id] ==
                                            KioskPermissionState.granted ||
                                        states[config.id] ==
                                            KioskPermissionState.notRequired ||
                                        states[config.id] ==
                                            KioskPermissionState.limited
                                    ? Icons.check_circle
                                    : Icons.warning_amber,
                              ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  const Text(
                    'PRE-FLIGHT CHECKLIST',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  for (final entry in _checks.entries)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        entry.value ? Icons.check_circle : Icons.error_outline,
                        color: entry.value ? Colors.green : Colors.orange,
                      ),
                      title: Text(entry.key),
                      subtitle:
                          entry.key == 'Network' ||
                              entry.key == 'Printer paired'
                          ? Text(
                              entry.value
                                  ? 'Ready — verify output with the admin test page.'
                                  : 'Optional — printing or uploads may be unavailable.',
                            )
                          : null,
                    ),
                  const Divider(),
                  for (final entry in widget.diagnostics.entries)
                    ListTile(
                      dense: true,
                      title: Text(entry.key),
                      subtitle: Text(entry.value),
                    ),
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 8,
                children: [
                  if (!widget.kioskLive)
                    OutlinedButton(
                      onPressed: _busy ? null : _requestPermissions,
                      child: const Text('Check / request setup permissions'),
                    ),
                  OutlinedButton(
                    onPressed: _busy ? null : _refresh,
                    child: const Text('Refresh checks'),
                  ),
                  if (widget.kioskLive)
                    FilledButton.tonal(
                      onPressed: _busy ? null : widget.onExitKiosk,
                      child: const Text('Exit kiosk mode'),
                    )
                  else
                    FilledButton(
                      onPressed: _busy ? null : _goLive,
                      child: const Text('Go live'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
