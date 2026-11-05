import 'package:flutter/material.dart';
import 'package:odon_booking/shared/widgets/odon_ui.dart';
import 'package:google_fonts/google_fonts.dart';
import 'ai_insights_service.dart';

class AiInsightsPage extends StatefulWidget {
  final DateTime selectedMonth;
  final DateTime? rangeEnd;
  final double totalRevenue;
  final double totalExpenses;
  final double totalSalaries;
  final double totalProfit;
  final List<Map<String, dynamic>> bookings;
  final List<Map<String, dynamic>> expenses;
  final List<Map<String, dynamic>> salaries;

  const AiInsightsPage({
    Key? key,
    required this.selectedMonth,
    this.rangeEnd,
    required this.totalRevenue,
    required this.totalExpenses,
    required this.totalSalaries,
    required this.totalProfit,
    required this.bookings,
    required this.expenses,
    required this.salaries,
  }) : super(key: key);

  @override
  _AiInsightsPageState createState() => _AiInsightsPageState();
}

class _AiInsightsPageState extends State<AiInsightsPage>
    with TickerProviderStateMixin {
  final AiInsightsService _aiService = AiInsightsService();
  Map<String, dynamic>? _insights;
  bool _isLoading = true;
  String? _error;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _generateInsights();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _generateInsights() async {
    try {
      final insights = await _aiService.generateBusinessInsights(
        selectedMonth: widget.selectedMonth,
        rangeStart: widget.selectedMonth,
        rangeEnd: widget.rangeEnd,
        totalRevenue: widget.totalRevenue,
        totalExpenses: widget.totalExpenses,
        totalSalaries: widget.totalSalaries,
        totalProfit: widget.totalProfit,
        bookings: widget.bookings,
        expenses: widget.expenses,
        salaries: widget.salaries,
      );

      setState(() {
        _insights = insights;
        _isLoading = false;
      });
      _animationController.forward();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Business insights'),
        actions: [
          IconButton(
            tooltip: 'Run again',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _isLoading ? null : () {
              setState(() {
                _isLoading = true;
                _error = null;
              });
              _generateInsights();
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _isLoading
          ? _buildLoadingView()
          : _error != null
          ? _buildErrorView()
          : _buildInsightsView(),
    );
  }

  Widget _buildLoadingView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(height: 20),
            Text('Reading this period\'s numbers…', style: AppText.headline),
            const SizedBox(height: 6),
            Text('Bookings, meals, expenses and salaries are being compared.',
                style: AppText.callout, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 80, color: AppColors.danger),
          const SizedBox(height: 16),
          Text(
            "Oops! Something went wrong",
            style: GoogleFonts.hankenGrotesk(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.danger,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _error!,
            style: GoogleFonts.hankenGrotesk(color: AppColors.ink3),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _isLoading = true;
                _error = null;
              });
              _generateInsights();
            },
            icon: const Icon(Icons.refresh),
            label: const Text("Try Again"),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.ink,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightsView() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SingleChildScrollView(
        padding: AppLayout.sliverPadding(context, maxWidth: AppLayout.maxForm, top: 16, bottom: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHealthOverview(),
            const SizedBox(height: 20),
            _buildKeyInsights(),
            const SizedBox(height: 20),
            _buildCriticalIssues(),
            const SizedBox(height: 20),
            _buildRevenueAnalysis(),
            const SizedBox(height: 20),
            _buildExpenseAnalysis(),
            const SizedBox(height: 20),
            _buildOperationalInsights(),
            const SizedBox(height: 20),
            _buildActionableRecommendations(),
            const SizedBox(height: 20),
            _buildPredictiveInsights(),
            const SizedBox(height: 20),
            _buildBenchmarkComparison(),

            const SizedBox(height: 20),
            _buildMealServiceAnalysis(),
            const SizedBox(height: 20),
            _buildRoomSalesAnalysis(),
            const SizedBox(height: 20),
            _buildExpenseOutliers(),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthOverview() {
    final health = _insights!['overallHealth'] ?? 'Fair';
    final score = _insights!['profitabilityScore'] ?? 70;

    Color healthColor;
    IconData healthIcon;

    switch (health.toLowerCase()) {
      case 'excellent':
        healthColor = AppColors.success;
        healthIcon = Icons.trending_up;
        break;
      case 'good':
        healthColor = AppColors.info;
        healthIcon = Icons.thumb_up;
        break;
      case 'fair':
        healthColor = AppColors.warning;
        healthIcon = Icons.warning;
        break;
      default:
        healthColor = AppColors.danger;
        healthIcon = Icons.trending_down;
    }

    final scoreNum = (score is num ? score : num.tryParse('$score') ?? 0).toDouble();
    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('BUSINESS HEALTH', style: AppText.eyebrow),
                    const SizedBox(height: 6),
                    Text('$health', style: AppText.largeTitle.copyWith(color: healthColor)),
                  ],
                ),
              ),
              IconWell(healthIcon, color: healthColor, size: 48),
            ],
          ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: ProportionBar(scoreNum / 100, color: healthColor)),
            const SizedBox(width: 12),
            Text('${scoreNum.round()}/100', style: AppText.number(14)),
          ]),
        ],
      ),
    );
  }

  Widget _buildKeyInsights() {
    final insights = _insights!['keyInsights'] as List? ?? [];

    return _buildSection(
      title: "Key insights",
      child: Column(
        children: insights.map<Widget>((insight) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),

            ),
            child: Row(
              children: [
                Icon(Icons.lightbulb, color: AppColors.info),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    insight.toString(),
                    style: GoogleFonts.hankenGrotesk(fontSize: 14),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCriticalIssues() {
    final issues = _insights!['criticalIssues'] as List? ?? [];

    if (issues.isEmpty) return const SizedBox.shrink();

    return _buildSection(
      title: "Critical issues",
      child: Column(
        children: issues.map<Widget>((issue) {
          final urgency = issue['urgency'] ?? 'Medium';
          Color urgencyColor = urgency == 'High'
              ? AppColors.danger
              : urgency == 'Medium'
              ? AppColors.warning
              : AppColors.warning;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),

            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning, color: urgencyColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        issue['issue'].toString(),
                        style: GoogleFonts.hankenGrotesk(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: urgencyColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        urgency,
                        style: GoogleFonts.hankenGrotesk(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  issue['impact'].toString(),
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 13,
                    color: AppColors.ink2,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRevenueAnalysis() {
    final analysis = _insights!['revenueAnalysis'] as Map<String, dynamic>? ??
        {};

    return _buildSection(
      title: "Revenue analysis",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAnalysisCard(
            title: "Summary",
            content: analysis['summary']?.toString() ?? '',
            color: AppColors.success,
            icon: Icons.assessment,
          ),
          const SizedBox(height: 12),
          _buildAnalysisLists(
            "Strengths",
            analysis['strengths'] as List? ?? [],
            AppColors.success,
            Icons.trending_up,
          ),
          const SizedBox(height: 12),
          _buildAnalysisLists(
            "Concerns",
            analysis['concerns'] as List? ?? [],
            AppColors.warning,
            Icons.warning,
          ),
          const SizedBox(height: 12),
          _buildAnalysisLists(
            "Opportunities",
            analysis['opportunities'] as List? ?? [],
            AppColors.info,
            Icons.lightbulb,
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseAnalysis() {
    final analysis = _insights!['expenseAnalysis'] as Map<String, dynamic>? ??
        {};

    return _buildSection(
      title: "Expense analysis",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAnalysisCard(
            title: "Summary",
            content: analysis['summary']?.toString() ?? '',
            color: AppColors.danger,
            icon: Icons.receipt_long,
          ),
          const SizedBox(height: 12),
          _buildAnalysisLists(
            "Highest Categories",
            analysis['highestCategories'] as List? ?? [],
            AppColors.danger,
            Icons.trending_up,
          ),
          const SizedBox(height: 12),
          _buildAnalysisLists(
            "Inefficiencies",
            analysis['inefficiencies'] as List? ?? [],
            AppColors.warning,
            Icons.error,
          ),
          const SizedBox(height: 12),
          _buildAnalysisLists(
            "Optimization Tips",
            analysis['optimizationTips'] as List? ?? [],
            AppColors.success,
            Icons.tips_and_updates,
          ),
        ],
      ),
    );
  }

  Widget _buildOperationalInsights() {
    final insights = _insights!['operationalInsights'] as List? ?? [];

    return _buildSection(
      title: "Operational insights",
      child: Column(
        children: insights.map<Widget>((insight) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.sunken,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.hairlineStrong),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight['metric'].toString(),
                  style: GoogleFonts.hankenGrotesk(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Status: ${insight['status']}",
                  style: GoogleFonts.hankenGrotesk(fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  "Recommendation: ${insight['recommendation']}",
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 14,
                    color: AppColors.ink2,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildActionableRecommendations() {
    final recommendations = _insights!['actionableRecommendations'] as List? ??
        [];

    return _buildSection(
      title: "Actionable recommendations",
      child: Column(
        children: recommendations.map<Widget>((rec) {
          final priority = rec['priority'] ?? 'Medium';
          Color priorityColor = priority == 'High'
              ? AppColors.danger
              : priority == 'Medium'
              ? AppColors.warning
              : AppColors.success;

          IconData categoryIcon;
          switch (rec['category']?.toLowerCase()) {
            case 'revenue':
              categoryIcon = Icons.monetization_on;
              break;
            case 'expenses':
              categoryIcon = Icons.receipt_long;
              break;
            case 'operations':
              categoryIcon = Icons.settings;
              break;
            case 'marketing':
              categoryIcon = Icons.campaign;
              break;
            default:
              categoryIcon = Icons.star;
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(categoryIcon, color: priorityColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        rec['action'].toString(),
                        style: GoogleFonts.hankenGrotesk(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: priorityColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        priority,
                        style: GoogleFonts.hankenGrotesk(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  "Expected Impact: ${rec['expectedImpact']}",
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 14,
                    color: AppColors.success,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Timeframe: ${rec['timeframe']}",
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 14,
                    color: AppColors.ink3,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPredictiveInsights() {
    final insights = _insights!['predictiveInsights'] as List? ?? [];

    return _buildSection(
      title: "Predictive insights",
      child: Column(
        children: insights.map<Widget>((insight) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.sunken,
              borderRadius: BorderRadius.circular(12),

            ),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, color: AppColors.ink),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    insight.toString(),
                    style: GoogleFonts.hankenGrotesk(fontSize: 14),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBenchmarkComparison() {
    final benchmark = _insights!['benchmarkComparison'] as Map<String,
        dynamic>? ?? {};

    return _buildSection(
      title: "Industry benchmark comparison",
      child: Column(
        children: [
          _buildBenchmarkCard(
              "Profit Margin", benchmark['profitMargin']?.toString() ?? 'N/A'),
          const SizedBox(height: 12),
          _buildBenchmarkCard("Occupancy Rate",
              benchmark['occupancyRate']?.toString() ?? 'N/A'),
          const SizedBox(height: 12),
          _buildBenchmarkCard(
              "Revenue Per Room", benchmark['revpar']?.toString() ?? 'N/A'),
        ],
      ),
    );
  }

  Widget _buildSection({required String title, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppText.title.copyWith(fontSize: 18)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildAnalysisCard({
    required String title,
    required String content,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.hankenGrotesk(
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: GoogleFonts.hankenGrotesk(
              fontSize: 14,
              color: AppColors.ink2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisLists(String title, List items, Color color,
      IconData icon) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.hankenGrotesk(
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...items.map<Widget>((item) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 4,
                    height: 4,
                    margin: const EdgeInsets.only(top: 6, right: 8),
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item.toString(),
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 13,
                        color: AppColors.ink2,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildBenchmarkCard(String metric, String comparison) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Icon(Icons.bar_chart, color: AppColors.roomOnly),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metric,
                  style: GoogleFonts.hankenGrotesk(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppColors.roomOnly,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  comparison,
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 13,
                    color: AppColors.ink2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMealServiceAnalysis() {
    final analysis = _insights!['mealServiceAnalysis'] as Map<String, dynamic>? ?? {};

    return _buildSection(
      title: "Meal service analysis",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAnalysisCard(
            title: "Summary",
            content: analysis['summary']?.toString() ?? '',
            color: AppColors.warning,
            icon: Icons.restaurant,
          ),
          const SizedBox(height: 12),
          _buildMealAnalysisCard("Breakfast", analysis['breakfastAnalysis']?.toString() ?? ''),
          const SizedBox(height: 8),
          _buildMealAnalysisCard("Lunch", analysis['lunchAnalysis']?.toString() ?? ''),
          const SizedBox(height: 8),
          _buildMealAnalysisCard("Dinner", analysis['dinnerAnalysis']?.toString() ?? ''),
          const SizedBox(height: 12),
          _buildAnalysisLists(
            "Cost Optimization",
            analysis['costOptimization'] as List? ?? [],
            AppColors.success,
            Icons.savings,
          ),
          if (analysis['staffingInsights']?.toString().isNotEmpty == true) ...[
            const SizedBox(height: 12),
            _buildAnalysisCard(
              title: "Staffing Insights",
              content: analysis['staffingInsights']?.toString() ?? '',
              color: AppColors.info,
              icon: Icons.people,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMealAnalysisCard(String mealType, String analysis) {
    IconData icon;
    Color color;

    switch (mealType.toLowerCase()) {
      case 'breakfast':
        icon = Icons.free_breakfast;
        color = AppColors.warning;
        break;
      case 'lunch':
        icon = Icons.lunch_dining;
        color = AppColors.success;
        break;
      case 'dinner':
        icon = Icons.dinner_dining;
        color = AppColors.danger;
        break;
      default:
        icon = Icons.restaurant;
        color = AppColors.warning;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mealType,
                  style: GoogleFonts.hankenGrotesk(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 14,
                  ),
                ),
                Text(
                  analysis,
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 12,
                    color: AppColors.ink2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomSalesAnalysis() {
    final analysis = _insights!['roomSalesAnalysis'] as Map<String, dynamic>? ?? {};

    return _buildSection(
      title: "Room sales analysis",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAnalysisCard(
            title: "Summary",
            content: analysis['summary']?.toString() ?? '',
            color: AppColors.ink,
            icon: Icons.hotel,
          ),
          const SizedBox(height: 12),
          _buildRoomTypeCard("Double Room", analysis['doubleRoomPerformance']?.toString() ?? '', Icons.bed),
          const SizedBox(height: 8),
          _buildRoomTypeCard("Triple Room", analysis['tripleRoomPerformance']?.toString() ?? '', Icons.king_bed),
          const SizedBox(height: 8),
          _buildRoomTypeCard("Family Room", analysis['familyRoomPerformance']?.toString() ?? '', Icons.family_restroom),
          const SizedBox(height: 8),
          _buildRoomTypeCard("Family Plus", analysis['familyPlusPerformance']?.toString() ?? '', Icons.groups),
          const SizedBox(height: 12),
          _buildAnalysisLists(
            "Recommendations",
            analysis['recommendations'] as List? ?? [],
            AppColors.info,
            Icons.lightbulb,
          ),
        ],
      ),
    );
  }

  Widget _buildRoomTypeCard(String roomType, String analysis, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.ink.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.ink.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.ink, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  roomType,
                  style: GoogleFonts.hankenGrotesk(
                    fontWeight: FontWeight.bold,
                    color: AppColors.ink,
                    fontSize: 14,
                  ),
                ),
                Text(
                  analysis,
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 12,
                    color: AppColors.ink2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseOutliers() {
    final outliers = _insights!['expenseOutliers'] as List? ?? [];

    if (outliers.isEmpty) return const SizedBox.shrink();

    return _buildSection(
      title: "High-impact expenses",
      child: Column(
        children: outliers.map<Widget>((outlier) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning, color: AppColors.danger),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        outlier['vendor'].toString(),
                        style: GoogleFonts.hankenGrotesk(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppColors.danger,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "${outlier['percentageOfRevenue'] ?? outlier['percentage']}%",
                        style: GoogleFonts.hankenGrotesk(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  "Amount: LKR ${outlier['amount'].toString()}",
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.danger,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Impact: ${outlier['impact']}",
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 14,
                    color: AppColors.ink2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Recommendation: ${outlier['recommendation']}",
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 14,
                    color: AppColors.success,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}