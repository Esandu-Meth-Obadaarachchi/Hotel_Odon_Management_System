import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Thrown when the backend rejects the caller's sign-in — either no/expired
/// token, or an account that is not on the allow-list.
class ApiAuthException implements Exception {
  ApiAuthException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  bool get isNotAllowed => statusCode == 403;

  @override
  String toString() => message;
}

class ApiService {
  // Switch back to Railway URL after rehosting the backend
  //final String baseUrl = 'http://192.168.1.26:3000';
  final String baseUrl = 'https://odonbookingflutterapp-production.up.railway.app';
  // Android emulator: use http://10.0.2.2:3000
  // Physical device: use your machine's local IP, e.g. http://192.168.1.26:3000
  //http://localhost:3000

  // ── Auth ───────────────────────────────────────────────────────────────────
  //
  // Every request carries the signed-in user's Firebase ID token. The backend
  // verifies it against Google's public keys and stamps createdBy/updatedBy
  // from the verified claims, so "who made this booking" cannot be spoofed by
  // a client.
  //
  // Firebase is currently only initialised on web ([main.dart]), so on mobile
  // there is no token yet and requests go out unauthenticated — the backend
  // accepts those while AUTH_ENFORCE is off. Once mobile sign-in is added this
  // starts returning tokens with no change needed here.

  Future<String?> _idToken() async {
    try {
      return await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {
      // Firebase not initialised on this platform (mobile, for now).
      return null;
    }
  }

  Future<Map<String, String>> _headers([Map<String, String>? extra]) async {
    final headers = <String, String>{...?extra};
    final token = await _idToken();
    if (token != null) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  /// Surfaces auth failures as [ApiAuthException] so screens can show
  /// "please sign in again" instead of a generic failure message.
  http.Response _check(http.Response res) {
    if (res.statusCode == 401 || res.statusCode == 403) {
      String message;
      try {
        message = (jsonDecode(res.body) as Map)['message']?.toString() ??
            'Not authorised';
      } catch (_) {
        message = res.statusCode == 403
            ? 'This account is not allowed to use the app'
            : 'Please sign in again';
      }
      throw ApiAuthException(res.statusCode, message);
    }
    return res;
  }

  Future<http.Response> _get(Uri url, {Map<String, String>? headers}) async =>
      _check(await http.get(url, headers: await _headers(headers)));

  Future<http.Response> _post(Uri url,
          {Map<String, String>? headers, Object? body}) async =>
      _check(await http.post(url, headers: await _headers(headers), body: body));

  Future<http.Response> _put(Uri url,
          {Map<String, String>? headers, Object? body}) async =>
      _check(await http.put(url, headers: await _headers(headers), body: body));

  Future<http.Response> _delete(Uri url,
          {Map<String, String>? headers, Object? body}) async =>
      _check(await http.delete(url, headers: await _headers(headers), body: body));

  // ── Identity & access management ───────────────────────────────────────────

  /// Asks the server who the signed-in user is and whether they may use the
  /// dashboard. Returns null when the server cannot answer — an old backend
  /// without this route, or no network — so the caller can fall back rather
  /// than lock the owner out. Throws [ApiAuthException] on a real refusal.
  Future<Map<String, dynamic>?> fetchMe() async {
    try {
      final res = await _get(Uri.parse('$baseUrl/me'));
      if (res.statusCode != 200) return null; // e.g. 404 on the old backend
      return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
    } on ApiAuthException {
      rethrow; // 403 = genuinely not allowed; the caller must honour it
    } catch (_) {
      return null; // network/parse trouble — caller decides
    }
  }

  /// {emails: [...], owners: [...]} — owners are protected and cannot be removed.
  Future<Map<String, dynamic>> fetchAccessList() async {
    final res = await _get(Uri.parse('$baseUrl/admin/allowed-emails'));
    if (res.statusCode != 200) {
      throw Exception('Could not load the access list (${res.statusCode})');
    }
    return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
  }

  Future<Map<String, dynamic>> addAllowedEmail(String email) async {
    final res = await _post(
      Uri.parse('$baseUrl/admin/allowed-emails'),
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: jsonEncode({'email': email}),
    );
    if (res.statusCode != 201) {
      throw Exception(_messageOf(res, 'Could not add that address'));
    }
    return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
  }

  Future<Map<String, dynamic>> removeAllowedEmail(String email) async {
    final res = await _delete(
      Uri.parse('$baseUrl/admin/allowed-emails/${Uri.encodeComponent(email)}'),
    );
    if (res.statusCode != 200) {
      throw Exception(_messageOf(res, 'Could not remove that address'));
    }
    return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
  }

  String _messageOf(http.Response res, String fallback) {
    try {
      return (jsonDecode(res.body) as Map)['message']?.toString() ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  Future<List<Map<String, dynamic>>> fetchFutureBookings(DateTime fromDate) async {
    //final String baseUrl = await _getBaseUrl();
    final response = await _get(Uri.parse('$baseUrl/bookings?fromCheckIn=${fromDate.toIso8601String()}'));
    if (response.statusCode == 200) {
      List<dynamic> data = jsonDecode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to fetch future bookings123: ${response.reasonPhrase}');
    }
  }

  // Fetch bookings for the selected date range
  Future<List<Map<String, dynamic>>> fetchBookingsForDateRange(DateTime checkInDate, DateTime checkOutDate) async {
    //final String baseUrl = await _getBaseUrl();
    final String checkIn = checkInDate.toIso8601String();
    final String checkOut = checkOutDate.toIso8601String();

    final url = Uri.parse('$baseUrl/bookings?checkIn=$checkIn&checkOut=$checkOut');

    try {
      final response = await _get(url);

      if (response.statusCode == 200) {
        // Parse the response and convert it into a List of Maps
        final List<dynamic> data = json.decode(response.body);
        return data.map((booking) => booking as Map<String, dynamic>).toList();
      } else {
        throw Exception('Failed to fetch bookings123');
      }
    } catch (e) {
      print('Error fetching bookings123: $e');
      throw Exception('Failed to fetch bookings123');
    }
  }

  Future<List<Map<String, dynamic>>> fetchBookingsForMonth(DateTime month) async {
    //final String baseUrl = await _getBaseUrl();
    // Get the start and end of the selected month
    final String startOfMonth = DateTime(month.year, month.month, 1).toIso8601String();
    final String endOfMonth = DateTime(month.year, month.month + 1, 0).toIso8601String();

    // API call to fetch bookings where checkIn and checkOut fall within the selected month
    final response = await _get(Uri.parse('$baseUrl/bookings?checkInStart=$startOfMonth&checkOutEnd=$endOfMonth'));

    if (response.statusCode == 200) {
      List<dynamic> data = jsonDecode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to fetch bookings for the selected month: ${response.reasonPhrase}');
    }
  }


  Future<List<Map<String, dynamic>>> fetchBookings(DateTime date) async {
    //final String baseUrl = await _getBaseUrl();
    final response = await _get(Uri.parse('$baseUrl/bookings?checkIn=${date.toIso8601String()}'));

    if (response.statusCode == 200) {
      List<dynamic> bookings = json.decode(response.body);
      return bookings.map((booking) => Map<String, dynamic>.from(booking)).toList();
    } else {
      throw Exception('Failed to load bookings: ${response.reasonPhrase}');
    }
  }

  Future<void> updateBooking(String id, Map<String, dynamic> updatedBooking) async {
    final response = await _put(
      Uri.parse('$baseUrl/bookings/$id'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(updatedBooking),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update booking: ${response.reasonPhrase}');
    }
  }

  Future<void> deleteBooking(String id) async {
    //final String baseUrl = await _getBaseUrl();
    final response = await _delete(Uri.parse('$baseUrl/bookings/$id'));

    if (response.statusCode != 200) {
      throw Exception('Failed to delete booking: ${response.body}');
    }
  }

  Future<void> addBooking(Map<String, dynamic> newBooking) async {
    //final String baseUrl = await _getBaseUrl();
    final response = await _post(
      Uri.parse('$baseUrl/bookings'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(newBooking),
    );

    if (response.statusCode != 201) {
      throw Exception('Failed to add booking: ${response.reasonPhrase}');
    }
  }

  Future<void> addInventory(Map<String, dynamic> newBooking) async {
    //final String baseUrl = await _getBaseUrl();
    final response = await _post(
      Uri.parse('$baseUrl/inventory'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(newBooking),
    );

    if (response.statusCode != 201) {
      throw Exception('Failed to add booking: ${response.reasonPhrase}');
    }
  }

  Future<List<dynamic>> fetchInventoryItems() async {
    final response = await _get(
      Uri.parse('$baseUrl/inventory'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    } else {
      throw Exception('Failed to fetch inventory items: ${response.reasonPhrase}');
    }
  }

  Future<void> updateInventoryItem(String id, Map<String, dynamic> updatedItem) async {
    final response = await _put(
      Uri.parse('$baseUrl/inventory/$id'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(updatedItem),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update inventory item: ${response.reasonPhrase}');
    }
  }

  // SALARY METHODS
  Future<List<Map<String, dynamic>>> fetchSalaries() async {
    final response = await _get(Uri.parse('$baseUrl/salaries'));
    if (response.statusCode == 200) {
      List<dynamic> data = jsonDecode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to fetch salaries: ${response.reasonPhrase}');
    }
  }

  Future<void> addSalary(Map<String, dynamic> salaryData) async {
    final response = await _post(
      Uri.parse('$baseUrl/salaries'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(salaryData),
    );

    if (response.statusCode != 201) {
      throw Exception('Failed to add salary: ${response.reasonPhrase}');
    }
  }

  Future<void> updateSalary(String id, Map<String, dynamic> salaryData) async {
    final response = await _put(
      Uri.parse('$baseUrl/salaries/$id'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(salaryData),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update salary: ${response.reasonPhrase}');
    }
  }

  Future<void> deleteSalary(String id) async {
    final response = await _delete(Uri.parse('$baseUrl/salaries/$id'));
    if (response.statusCode != 200) {
      throw Exception('Failed to delete salary: ${response.reasonPhrase}');
    }
  }

  // EXPENSE METHODS
  Future<List<Map<String, dynamic>>> fetchExpenses() async {
    final response = await _get(Uri.parse('$baseUrl/expenses'));
    if (response.statusCode == 200) {
      List<dynamic> data = jsonDecode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to fetch expenses: ${response.reasonPhrase}');
    }
  }

  Future<void> addExpense(Map<String, dynamic> expenseData) async {
    final response = await _post(
      Uri.parse('$baseUrl/expenses'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(expenseData),
    );

    if (response.statusCode != 201) {
      throw Exception('Failed to add expense: ${response.reasonPhrase}');
    }
  }

  Future<void> updateExpense(String id, Map<String, dynamic> expenseData) async {
    final response = await _put(
      Uri.parse('$baseUrl/expenses/$id'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(expenseData),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update expense: ${response.reasonPhrase}');
    }
  }

  Future<void> deleteExpense(String id) async {
    final response = await _delete(Uri.parse('$baseUrl/expenses/$id'));
    if (response.statusCode != 200) {
      throw Exception('Failed to delete expense: ${response.reasonPhrase}');
    }
  }


  // Fetch expenses for a specific month
  Future<List<Map<String, dynamic>>> fetchExpensesForMonth(DateTime month) async {
    final response = await _get(
        Uri.parse('$baseUrl/expenses/month/${month.year}/${month.month}')
    );
    if (response.statusCode == 200) {
      List<dynamic> data = jsonDecode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to fetch expenses for month: ${response.reasonPhrase}');
    }
  }

// Fetch salaries for a specific month
  Future<List<Map<String, dynamic>>> fetchSalariesForMonth(DateTime month) async {
    final response = await _get(
        Uri.parse('$baseUrl/salaries/month/${month.year}/${month.month}')
    );
    if (response.statusCode == 200) {
      List<dynamic> data = jsonDecode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to fetch salaries for month: ${response.reasonPhrase}');
    }
  }

  Future<void> deleteInventoryItem(String id) async {
    final response = await _delete(
      Uri.parse('$baseUrl/inventory/$id'),
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete inventory item: ${response.reasonPhrase}');
    }
  }


  // ROOM CONFIG METHODS

  Future<Map<String, dynamic>> fetchRoomConfig() async {
    final response = await _get(Uri.parse('$baseUrl/room-config'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to fetch room config: ${response.reasonPhrase}');
    }
  }

  Future<void> updateRoomConfig(List<Map<String, dynamic>> rooms) async {
    final response = await _put(
      Uri.parse('$baseUrl/room-config'),
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: jsonEncode({'rooms': rooms}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update room config: ${response.reasonPhrase}');
    }
  }

  // GUEST METHODS

  Future<List<Map<String, dynamic>>> fetchGuests() async {
    final response = await _get(Uri.parse('$baseUrl/guests'));
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to fetch guests: ${response.reasonPhrase}');
    }
  }

  Future<List<Map<String, dynamic>>> searchGuests(String query) async {
    final url = Uri.parse('$baseUrl/guests/search?q=${Uri.encodeQueryComponent(query)}');
    final response = await _get(url);
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to search guests: ${response.reasonPhrase}');
    }
  }

  Future<Map<String, dynamic>> fetchGuest(String phone) async {
    final response = await _get(Uri.parse('$baseUrl/guests/${Uri.encodeComponent(phone)}'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to fetch guest: ${response.reasonPhrase}');
    }
  }

  Future<List<Map<String, dynamic>>> fetchGuestBookings(String phone) async {
    final response = await _get(Uri.parse('$baseUrl/guests/${Uri.encodeComponent(phone)}/bookings'));
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to fetch guest bookings: ${response.reasonPhrase}');
    }
  }

  // PRICE CONFIG METHODS

  Future<Map<String, dynamic>> fetchPrices() async {
    final response = await _get(Uri.parse('$baseUrl/prices'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to fetch prices: ${response.reasonPhrase}');
    }
  }

  Future<void> updatePrices(
      Map<String, Map<String, double>> packages, double driverRoomPrice) async {
    final response = await _put(
      Uri.parse('$baseUrl/prices'),
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: jsonEncode({
        'packages': packages,
        'driverRoomPrice': driverRoomPrice,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update prices: ${response.reasonPhrase}');
    }
  }
}



//ipconfig getifaddr en0