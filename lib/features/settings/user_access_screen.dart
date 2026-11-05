import 'package:flutter/material.dart';
import 'package:odon_booking/shared/widgets/odon_ui.dart';
import 'package:odon_booking/core/api/api_service.dart';

/// Owner-only screen for granting and revoking dashboard access.
///
/// The list lives on the server, so changes take effect for everyone without a
/// rebuild or redeploy. Owner accounts are shown but cannot be removed — that
/// rule is enforced by the backend, not just hidden here.
class UserAccessScreen extends StatefulWidget {
  const UserAccessScreen({super.key});

  @override
  State<UserAccessScreen> createState() => _UserAccessScreenState();
}

class _UserAccessScreenState extends State<UserAccessScreen> {
  final _api = ApiService();
  final _emailController = TextEditingController();

  List<String> _emails = [];
  List<String> _owners = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.fetchAccessList();
      if (!mounted) return;
      setState(() {
        _emails =
            List<String>.from((data['emails'] as List? ?? []).map((e) => '$e'));
        _owners =
            List<String>.from((data['owners'] as List? ?? []).map((e) => '$e'));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _clean(e);
      });
    }
  }

  Future<void> _add() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await _api.addAllowedEmail(email);
      if (!mounted) return;
      setState(() {
        _emails =
            List<String>.from((data['emails'] as List? ?? []).map((e) => '$e'));
        _owners =
            List<String>.from((data['owners'] as List? ?? []).map((e) => '$e'));
        _busy = false;
      });
      _emailController.clear();
      _toast('$email can now sign in');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _clean(e);
      });
    }
  }

  Future<void> _remove(String email) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove access?'),
        content: Text(
          '$email will no longer be able to sign in to the dashboard. '
          'Bookings they entered are kept, along with their name on them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await _api.removeAllowedEmail(email);
      if (!mounted) return;
      setState(() {
        _emails =
            List<String>.from((data['emails'] as List? ?? []).map((e) => '$e'));
        _owners =
            List<String>.from((data['owners'] as List? ?? []).map((e) => '$e'));
        _busy = false;
      });
      _toast('$email can no longer sign in');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _clean(e);
      });
    }
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '');

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User access'),
        actions: [
          IconButton(
            tooltip: 'Reload',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const LoadingView()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: AppLayout.sliverPadding(context,
                    maxWidth: AppLayout.maxForm, top: 16, bottom: 32),
                children: [
                  _intro(),
                  const SizedBox(height: 16),
                  _addCard(),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _errorBanner(_error!),
                  ],
                  FormSectionLabel('Who can sign in · ${_emails.length}'),
                  if (_emails.isNotEmpty)
                    SurfaceCard(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(children: [
                        for (var i = 0; i < _emails.length; i++) ...[
                          if (i > 0)
                            const Padding(
                                padding: EdgeInsets.only(left: 64),
                                child: Divider()),
                          _row(_emails[i]),
                        ],
                      ]),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _intro() => const InlineBanner(
        'Only these Google accounts can sign in. Changes apply within a minute. '
        'Every booking records who created and last edited it.',
      );

  Widget _addCard() => SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add a person', style: AppText.headline),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _emailController,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    onSubmitted: (_) => _busy ? null : _add(),
                    decoration: fieldDecoration('Google account',
                        hint: 'name@gmail.com',
                        icon: Icons.alternate_email_rounded),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _busy ? null : _add,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                  icon: _busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Use the exact Google account they sign in with.',
                style: AppText.footnote),
          ],
        ),
      );

  Widget _errorBanner(String message) =>
      InlineBanner(message, tone: BannerTone.warning);

  Widget _row(String email) {
    final isOwner = _owners.contains(email);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          InitialsAvatar(
              email.split('@').first.replaceAll(RegExp(r'[._]'), ' '),
              size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(email,
                    style: AppText.bodyStrong.copyWith(fontSize: 14),
                    overflow: TextOverflow.ellipsis),
                if (isOwner)
                  Text('Owner · can\'t be removed',
                      style: AppText.footnote.copyWith(fontSize: 12)),
              ],
            ),
          ),
          if (isOwner)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: StatusPill('Owner', icon: Icons.shield_outlined),
            )
          else
            IconButton(
              tooltip: 'Remove access',
              onPressed: _busy ? null : () => _remove(email),
              icon: const Icon(Icons.remove_circle_outline_rounded,
                  size: 20, color: AppColors.ink3),
            ),
        ],
      ),
    );
  }
}
