import 'package:flutter/material.dart';
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
        _emails = List<String>.from((data['emails'] as List? ?? []).map((e) => '$e'));
        _owners = List<String>.from((data['owners'] as List? ?? []).map((e) => '$e'));
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
        _emails = List<String>.from((data['emails'] as List? ?? []).map((e) => '$e'));
        _owners = List<String>.from((data['owners'] as List? ?? []).map((e) => '$e'));
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
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
        _emails = List<String>.from((data['emails'] as List? ?? []).map((e) => '$e'));
        _owners = List<String>.from((data['owners'] as List? ?? []).map((e) => '$e'));
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
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text(
          'User Access',
          style: TextStyle(
              color: Colors.white, fontFamily: 'Outfit', fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.indigo,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'Reload',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _intro(),
                  const SizedBox(height: 16),
                  _addCard(),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _errorBanner(_error!),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    'WHO CAN SIGN IN (${_emails.length})',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._emails.map(_row),
                ],
              ),
            ),
    );
  }

  Widget _intro() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.indigo.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.indigo.shade100),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 18, color: Colors.indigo.shade400),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Only these Google accounts can sign in. Changes apply within a '
                'minute — no new app version needed. Every booking records the '
                'account that created and last edited it.',
                style: TextStyle(fontSize: 13, color: Color(0xFF334155), height: 1.4),
              ),
            ),
          ],
        ),
      );

  Widget _addCard() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Add a person',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _emailController,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    onSubmitted: (_) => _busy ? null : _add(),
                    decoration: InputDecoration(
                      hintText: 'name@gmail.com',
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _busy ? null : _add,
                  icon: _busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'It must be the Google account they sign in with, spelled exactly.',
              style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
      );

  Widget _errorBanner(String message) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 18, color: Colors.red.shade400),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message,
                  style: TextStyle(fontSize: 13, color: Colors.red.shade700)),
            ),
          ],
        ),
      );

  Widget _row(String email) {
    final isOwner = _owners.contains(email);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isOwner ? Colors.indigo.shade100 : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor:
                isOwner ? Colors.indigo.shade50 : const Color(0xFFF1F5F9),
            child: Icon(
              isOwner ? Icons.shield_rounded : Icons.person_outline,
              size: 16,
              color: isOwner ? Colors.indigo : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(email,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
                if (isOwner)
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Text('Owner — cannot be removed',
                        style: TextStyle(fontSize: 11, color: Colors.indigo)),
                  ),
              ],
            ),
          ),
          if (!isOwner)
            IconButton(
              tooltip: 'Remove access',
              onPressed: _busy ? null : () => _remove(email),
              icon: Icon(Icons.delete_outline, size: 20, color: Colors.red.shade400),
            ),
        ],
      ),
    );
  }
}
