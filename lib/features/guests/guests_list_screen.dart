import 'package:flutter/material.dart';
import 'package:odon_booking/shared/widgets/odon_ui.dart';
import 'package:intl/intl.dart';
import 'package:odon_booking/core/api/api_service.dart';
import 'guest_detail_screen.dart';

class GuestsListScreen extends StatefulWidget {
  const GuestsListScreen({super.key});

  @override
  State<GuestsListScreen> createState() => _GuestsListScreenState();
}

class _GuestsListScreenState extends State<GuestsListScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _allGuests = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadGuests();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadGuests() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final guests = await _api.fetchGuests();
      if (!mounted) return;
      setState(() {
        _allGuests = guests;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  List<Map<String, dynamic>> get _filteredGuests {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _allGuests;
    return _allGuests.where((g) {
      final name = (g['name'] ?? '').toString().toLowerCase();
      final phone = (g['phone'] ?? '').toString().toLowerCase();
      return name.contains(q) || phone.contains(q);
    }).toList();
  }

  int get _totalBookings => _allGuests.fold<int>(
      0, (sum, g) => sum + ((g['bookingCount'] as num?)?.toInt() ?? 0));

  @override
  Widget build(BuildContext context) {
    final guests = _filteredGuests;

    return Scaffold(
      appBar: AppBar(title: const Text('Guests')),
      body: PageBody(
        maxWidth: AppLayout.maxForm,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            MetricStrip([
              Metric('${_allGuests.length}', 'Guests'),
              Metric('$_totalBookings', 'Bookings'),
            ], valueSize: 24),
            const SizedBox(height: 12),
            _buildSearchBar(),
            const SizedBox(height: 12),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadGuests,
                child: _buildBody(guests),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'Search by name or phone',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => _searchController.clear(),
              ),
      ),
    );
  }

  Widget _buildBody(List<Map<String, dynamic>> guests) {
    if (_loading) return const LoadingView();
    if (_error != null) {
      return ListView(children: [
        EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Couldn\'t load guests',
          message: 'Pull down to try again.',
          actionLabel: 'Retry',
          onAction: _loadGuests,
        ),
      ]);
    }
    if (guests.isEmpty) {
      final searching = _searchController.text.isNotEmpty;
      return ListView(children: [
        EmptyState(
          icon: searching
              ? Icons.search_off_rounded
              : Icons.people_outline_rounded,
          title: searching
              ? 'No match for "${_searchController.text}"'
              : 'No guests yet',
          message: searching
              ? 'Try part of the name or the last digits of the phone number.'
              : 'Guests are added automatically when a booking is saved with a phone number.',
        ),
      ]);
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        SurfaceCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < guests.length; i++) ...[
                if (i > 0)
                  const Padding(
                      padding: EdgeInsets.only(left: 70), child: Divider()),
                _buildGuestCard(guests[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGuestCard(Map<String, dynamic> guest) {
    final name = (guest['name'] ?? 'Guest').toString();
    final phone = (guest['phone'] ?? '').toString();
    final bookingCount = (guest['bookingCount'] as num?)?.toInt() ?? 0;
    final lastBookingRaw = guest['lastBooking'];
    final lastBooking = lastBookingRaw is String && lastBookingRaw.isNotEmpty
        ? DateTime.tryParse(lastBookingRaw)
        : null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => GuestDetailScreen(guest: guest)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              InitialsAvatar(name, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: AppText.bodyStrong,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (phone.isNotEmpty) phone,
                        if (lastBooking != null)
                          'Last stay ${DateFormat('d MMM yyyy').format(lastBooking)}',
                      ].join(' · '),
                      style: AppText.footnote,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _bookingPill(bookingCount),
              const Icon(Icons.chevron_right_rounded, color: AppColors.ink4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bookingPill(int count) {
    if (count > 1) return StatusPill('$count stays', color: AppColors.success);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Text('$count stay${count == 1 ? '' : 's'}',
          style: AppText.footnote.copyWith(fontSize: 12)),
    );
  }
}
