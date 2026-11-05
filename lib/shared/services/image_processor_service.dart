//AIzaSyBj3LrgKOM8dmQqu9SWeiqmj2CUjG-tmSM
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:odon_booking/shared/widgets/odon_ui.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

class ImageProcessorService {
  static const String _geminiApiKey = 'AIzaSyAV0JeIGdcTSkGU5mRvGVjFt248jRTzWpk'; // Replace with your actual API key
  static const String _geminiApiUrl = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent';

  final ImagePicker _picker = ImagePicker();

  // Updated method - no longer needs type parameter since we extract everything
  Future<List<Map<String, dynamic>>> processImage(BuildContext context) async {
    try {
      print('Starting image processing for all data');

      // Show image source selection dialog
      final ImageSource? source = await _showImageSourceDialog(context);
      if (source == null) {
        print('No image source selected');
        return [];
      }

      print('Image source selected: $source');

      // Pick image
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 95, // Increased quality for better OCR
      );
      if (image == null) {
        print('No image selected');
        return [];
      }

      print('Image selected: ${image.path}');

      // Convert image to base64
      final bytes = await image.readAsBytes();
      final base64Image = base64Encode(bytes);
      print('Image converted to base64, size: ${base64Image.length} characters');

      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('Processing image with AI...'),
            ],
          ),
        ),
      );

      // Process with Gemini AI - now extracts all data
      final extractedData = await _processWithGemini(base64Image);

      // Close loading dialog
      Navigator.of(context).pop();

      print('Extraction completed, found ${extractedData.length} items');
      return extractedData;
    } catch (e) {
      // Close loading dialog if it's open
      try {
        Navigator.of(context).pop();
      } catch (_) {}

      print('Error in processImage: $e');
      throw Exception('Failed to process image: $e');
    }
  }

  Future<ImageSource?> _showImageSourceDialog(BuildContext context) async {
    return showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Select Image Source'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.camera_alt, color: AppColors.ink2),
              title: Text('Camera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library, color: AppColors.ink2),
              title: Text('Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
        ],
      ),
    );
  }

  // Updated method - now extracts all data without type filtering
  Future<List<Map<String, dynamic>>> _processWithGemini(String base64Image) async {
    try {
      print('Sending request to Gemini API...');
      final prompt = _getEnhancedPrompt();

      final requestBody = {
        'contents': [
          {
            'parts': [
              {
                'text': prompt,
              },
              {
                'inline_data': {
                  'mime_type': 'image/jpeg',
                  'data': base64Image,
                }
              }
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.2,
          'topK': 40,
          'topP': 0.95,
          'maxOutputTokens': 32768,
          // Newer Gemini models enable "thinking" by default, which eats the
          // output-token budget and truncates the JSON after only a few rows.
          // thinkingBudget: 0 disables it so the whole budget goes to output.
          'thinkingConfig': {
            'thinkingBudget': 0,
          },
        }
      };

      print('Making HTTP request to Gemini...');
      final response = await http.post(
        Uri.parse('$_geminiApiUrl?key=$_geminiApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      print('Response status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['candidates'] != null && data['candidates'].isNotEmpty) {
          final candidate = data['candidates'][0];
          final finishReason = candidate['finishReason'];
          if (finishReason != null && finishReason != 'STOP') {
            print('WARNING: Gemini finishReason="$finishReason" — output was '
                'cut off. Some records may be missing.');
          }
          final text = candidate['content']['parts'][0]['text'];
          print('Gemini response text: $text');
          return _parseGeminiResponse(text);
        } else {
          print('No candidates in response');
          throw Exception('No data extracted from image - candidates empty');
        }
      } else if (response.statusCode == 400) {
        print('Bad request - likely API key issue or invalid request format');
        throw Exception('Invalid API request. Please check your API key.');
      } else if (response.statusCode == 403) {
        print('Forbidden - API key might be invalid or quota exceeded');
        throw Exception('API access denied. Please check your API key.');
      } else {
        print('API error: ${response.statusCode} - ${response.body}');
        throw Exception('Gemini API error: ${response.statusCode}');
      }
    } catch (e) {
      print('Exception in _processWithGemini: $e');
      rethrow;
    }
  }

  // Enhanced prompt with specific instructions for date extraction
  String _getEnhancedPrompt() {
    final currentYear = DateTime.now().year;
    return '''
IMPORTANT: Analyze this financial ledger/document image very carefully and extract EVERY SINGLE entry — do NOT stop early, do NOT summarize, do NOT skip rows. You must output ALL items found in the image.

CRITICAL DATE EXTRACTION RULES:
- Look for dates on the LEFT SIDE of each row/line
- Dates are typically in MM-DD format (like 07-02, 07-05, 09-01, etc.)
- The month comes FIRST, then the day (MM-DD)
- Convert these to full dates using current year ($currentYear)
- If you see "07-02", convert it to "2025-07-02T00:00:00.000Z"
- If you see "09-01", convert it to "2025-09-01T00:00:00.000Z"
- Pay close attention to the leftmost column for these date patterns

DATA EXTRACTION RULES:
1. Extract EVERY line that has both a description/name AND an amount
2. Look for patterns like:
   - "ROOM" entries with amounts
   - Person names with salary amounts
   - Service/item descriptions with costs
   - Bills and expenses

3. For each entry, determine if it's:
   - SALARY: If it looks like a person's name or salary-related term
   - EXPENSE: If it looks like a service, item, bill, or cost

FORMAT REQUIREMENTS - Return ONLY valid JSON array:
[
  {
    "itemName": "ROOM" or "John Doe" or "ELECTRICITY BILL",
    "amount": 25000,
    "date": "2025-07-02T00:00:00.000Z",
    "suggestedType": "salary" or "expense",
    "suggestedCategory": "Monthly" or "Food" or "Utilities" etc,
    "description": "Additional context if visible"
  }
]

CATEGORY MAPPING:
- For SALARY type: use "Monthly", "Weekly", "OT", "Commission"
- For EXPENSE type: use "Food", "Utilities", "Maintenance", "Supplies", "Transportation", "Marketing", "Equipment", "Other"

AMOUNT PROCESSING:
- Extract numeric values only
- Remove currency symbols, commas, spaces
- Convert to number format

QUALITY CONTROL:
- Only include entries where BOTH name AND amount are clearly visible
- Double-check date extraction - this is CRITICAL
- Ignore entries that are unclear or ambiguous
- Return empty array [] if no clear data found
- YOU MUST include every row — if the image has 10 rows, return 10 items; if it has 20, return 20

Return ONLY the JSON array, no explanations or additional text. Do not truncate the output.
''';
  }

  // Enhanced parsing method with better error handling
  List<Map<String, dynamic>> _parseGeminiResponse(String response) {
    try {
      print('Raw response length: ${response.length}');
      print('Raw response: $response');

      // Clean the response to extract JSON
      String cleanedResponse = response.trim();

      // Remove markdown formatting if present
      cleanedResponse = cleanedResponse.replaceAll('```json', '').replaceAll('```', '').trim();

      // Try to find JSON array in the response
      final jsonStart = cleanedResponse.indexOf('[');
      final jsonEnd = cleanedResponse.lastIndexOf(']');

      print('JSON start: $jsonStart, JSON end: $jsonEnd');

      // If we have a complete JSON array, try to parse it normally
      if (jsonStart != -1 && jsonEnd != -1 && jsonEnd > jsonStart) {
        final jsonString = cleanedResponse.substring(jsonStart, jsonEnd + 1);
        print('Extracted JSON string: $jsonString');

        try {
          final List<dynamic> jsonArray = jsonDecode(jsonString);
          print('Successfully parsed JSON array with ${jsonArray.length} items');

          // Convert to List<Map<String, dynamic>> and validate data
          final result = jsonArray.map((item) {
            if (item is Map<String, dynamic>) {
              final parsedItem = {
                'itemName': item['itemName']?.toString().trim() ?? '',
                'amount': _parseAmount(item['amount']),
                'date': _parseAndValidateDate(item['date']),
                'suggestedType': _validateType(item['suggestedType']?.toString()),
                'suggestedCategory': _validateCategory(item['suggestedCategory']?.toString(), _validateType(item['suggestedType']?.toString())),
                'description': item['description']?.toString().trim() ?? '',
              };
              print('Parsed item: $parsedItem');
              return parsedItem;
            }
            return <String, dynamic>{};
          }).where((item) =>
          item.isNotEmpty &&
              item['itemName'] != '' &&
              (item['amount'] as double) > 0
          ).toList();

          print('Final result count: ${result.length}');
          return result;
        } catch (jsonError) {
          print('JSON decode error: $jsonError');
          // Fall through to incomplete JSON parsing
        }
      }

      // If normal JSON parsing failed or JSON is incomplete, try to extract objects manually
      print('Attempting to parse incomplete/malformed JSON...');
      return _parseIncompleteJson(cleanedResponse);

    } catch (e) {
      print('Error parsing Gemini response: $e');
      print('Response was: $response');
      return [];
    }
  }

  // Enhanced date parsing and validation
  String _parseAndValidateDate(dynamic dateInput) {
    if (dateInput == null) {
      return DateTime.now().toIso8601String();
    }

    final dateStr = dateInput.toString();

    // Try to parse existing ISO format
    final existingDate = DateTime.tryParse(dateStr);
    if (existingDate != null) {
      return existingDate.toIso8601String();
    }

    // Try to parse MM-DD format and convert to current year
    final mmDdPattern = RegExp(r'^(\d{1,2})-(\d{1,2})$');
    final match = mmDdPattern.firstMatch(dateStr);
    if (match != null) {
      final month = int.tryParse(match.group(1)!) ?? 1;
      final day = int.tryParse(match.group(2)!) ?? 1;
      final currentYear = DateTime.now().year;

      try {
        final parsedDate = DateTime(currentYear, month, day);
        return parsedDate.toIso8601String();
      } catch (e) {
        print('Error parsing MM-DD date: $e');
      }
    }

    // Fallback to current date
    return DateTime.now().toIso8601String();
  }

  // Validate and normalize type
  String _validateType(String? type) {
    if (type == null) return 'expense';
    final lowerType = type.toLowerCase().trim();
    return lowerType == 'salary' ? 'salary' : 'expense';
  }

  // Validate and normalize category based on type
  String _validateCategory(String? category, String type) {
    if (category == null) return type == 'salary' ? 'Monthly' : 'Other';

    final lowerCategory = category.toLowerCase().trim();

    if (type == 'salary') {
      const salaryCategories = ['monthly', 'weekly', 'ot', 'commission'];
      for (final cat in salaryCategories) {
        if (lowerCategory.contains(cat)) {
          return _capitalizeFirst(cat);
        }
      }
      return 'Monthly';
    } else {
      const expenseCategories = [
        'food', 'utilities', 'maintenance', 'supplies',
        'transportation', 'marketing', 'equipment', 'other'
      ];
      for (final cat in expenseCategories) {
        if (lowerCategory.contains(cat)) {
          return _capitalizeFirst(cat);
        }
      }
      return 'Other';
    }
  }

  String _capitalizeFirst(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1).toLowerCase();
  }

  // Helper method to parse incomplete JSON (enhanced)
  List<Map<String, dynamic>> _parseIncompleteJson(String jsonString) {
    try {
      print('Attempting to parse incomplete JSON...');

      List<Map<String, dynamic>> validItems = [];

      // Enhanced regex pattern to catch more object variations
      final objectPattern = RegExp(
          r'\{[^{}]*?"itemName"[^{}]*?"amount"[^{}]*?\}',
          multiLine: true,
          dotAll: true
      );
      final matches = objectPattern.allMatches(jsonString);

      print('Found ${matches.length} potential object matches');

      for (final match in matches) {
        try {
          String objectString = match.group(0)!;

          // Clean up the object string
          objectString = objectString
              .replaceAll(RegExp(r'\n\s*'), ' ')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();

          print('Trying to parse object: $objectString');

          final Map<String, dynamic> item = jsonDecode(objectString);

          if (item.containsKey('itemName') &&
              item.containsKey('amount') &&
              item['itemName'].toString().trim().isNotEmpty) {

            final parsedItem = {
              'itemName': item['itemName'].toString().trim(),
              'amount': _parseAmount(item['amount']),
              'date': _parseAndValidateDate(item['date']),
              'suggestedType': _validateType(item['suggestedType']?.toString()),
              'suggestedCategory': _validateCategory(
                  item['suggestedCategory']?.toString(),
                  _validateType(item['suggestedType']?.toString())
              ),
              'description': item['description']?.toString().trim() ?? '',
            };

            // Only add if amount is valid
            if ((parsedItem['amount'] as double) > 0) {
              validItems.add(parsedItem);
              print('Successfully parsed object: $parsedItem');
            }
          }
        } catch (e) {
          print('Failed to parse object: $e');
          continue;
        }
      }

      // If the regex approach didn't work, try line-by-line parsing
      if (validItems.isEmpty) {
        print('Regex approach failed, trying line-by-line parsing...');
        validItems = _parseLineByLine(jsonString);
      }

      print('Recovered ${validItems.length} items from incomplete JSON');
      return validItems;
    } catch (e) {
      print('Error in incomplete JSON parsing: $e');
      return [];
    }
  }

  // Enhanced line-by-line parsing
  List<Map<String, dynamic>> _parseLineByLine(String jsonString) {
    try {
      print('Attempting line-by-line parsing...');

      List<Map<String, dynamic>> validItems = [];
      final lines = jsonString.split('\n');

      String? currentItemName;
      double? currentAmount;
      String? currentDate;
      String? currentType;
      String? currentCategory;
      String? currentDescription;

      for (String line in lines) {
        line = line.trim().replaceAll(RegExp(r'[",]$'), '');

        if (line.contains('itemName')) {
          final parts = line.split(':');
          if (parts.length > 1) {
            currentItemName = parts[1].trim().replaceAll(RegExp(r'[",]'), '');
          }
        } else if (line.contains('amount')) {
          final parts = line.split(':');
          if (parts.length > 1) {
            currentAmount = _parseAmount(parts[1].trim().replaceAll(RegExp(r'[",]'), ''));
          }
        } else if (line.contains('date')) {
          final parts = line.split(':');
          if (parts.length > 1) {
            currentDate = parts[1].trim().replaceAll(RegExp(r'[",]'), '');
          }
        } else if (line.contains('suggestedType')) {
          final parts = line.split(':');
          if (parts.length > 1) {
            currentType = parts[1].trim().replaceAll(RegExp(r'[",]'), '');
          }
        } else if (line.contains('suggestedCategory')) {
          final parts = line.split(':');
          if (parts.length > 1) {
            currentCategory = parts[1].trim().replaceAll(RegExp(r'[",]'), '');
          }
        } else if (line.contains('description')) {
          final parts = line.split(':');
          if (parts.length > 1) {
            currentDescription = parts[1].trim().replaceAll(RegExp(r'[",]'), '');
          }
        }

        // When we hit a closing brace or start of new object, save current item
        if ((line.contains('}') || line.contains('{')) &&
            currentItemName != null &&
            currentAmount != null &&
            currentItemName.isNotEmpty &&
            currentAmount > 0) {

          final parsedItem = {
            'itemName': currentItemName,
            'amount': currentAmount,
            'date': _parseAndValidateDate(currentDate),
            'suggestedType': _validateType(currentType),
            'suggestedCategory': _validateCategory(currentCategory, _validateType(currentType)),
            'description': currentDescription ?? '',
          };
          validItems.add(parsedItem);
          print('Line-by-line parsed item: $parsedItem');

          // Reset for next item
          currentItemName = null;
          currentAmount = null;
          currentDate = null;
          currentType = null;
          currentCategory = null;
          currentDescription = null;
        }
      }

      print('Line-by-line parsing found ${validItems.length} items');
      return validItems;
    } catch (e) {
      print('Error in line-by-line parsing: $e');
      return [];
    }
  }

  double _parseAmount(dynamic amount) {
    if (amount is double) return amount;
    if (amount is int) return amount.toDouble();
    if (amount is String) {
      // Remove currency symbols, commas, spaces, and other non-numeric characters
      final cleanedAmount = amount.replaceAll(RegExp(r'[^\d.]'), '');
      final parsed = double.tryParse(cleanedAmount) ?? 0.0;
      return parsed;
    }
    return 0.0;
  }
}

// Add this global navigator key to your main.dart
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();