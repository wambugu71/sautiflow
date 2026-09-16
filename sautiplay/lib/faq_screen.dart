import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data/faq_data.dart';
import 'models/faq_item.dart';
import 'services/app_theme_service.dart';
import 'widgets/app_m3e_widgets.dart';

/// Dedicated FAQ Sub-Screen derived directly from site/index.html (Section 06).
class FaqScreen extends StatefulWidget {
  const FaqScreen({super.key});

  @override
  State<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends State<FaqScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _expandedIds = {};
  String _selectedCategory = 'All';
  String _searchQuery = '';

  List<String> get _categories {
    final categories = sautiplayFaqItems.map((e) => e.category).toSet().toList();
    categories.sort();
    return ['All', ...categories];
  }

  List<FaqItem> get _filteredFaqs {
    return sautiplayFaqItems.where((item) {
      // Filter by category
      if (_selectedCategory != 'All' && item.category != _selectedCategory) {
        return false;
      }
      // Filter by search query
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final inQuestion = item.question.toLowerCase().contains(query);
        final inAnswer = item.answer.toLowerCase().contains(query);
        final inCategory = item.category.toLowerCase().contains(query);
        final inTags = item.tags.any((tag) => tag.toLowerCase().contains(query));
        return inQuestion || inAnswer || inCategory || inTags;
      }
      return true;
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleExpand(String id) {
    setState(() {
      if (_expandedIds.contains(id)) {
        _expandedIds.remove(id);
      } else {
        _expandedIds.add(id);
      }
    });
  }

  void _copyToClipboard(FaqItem item) {
    final formatted = 'Q: ${item.question}\n\nA: ${item.answer}';
    Clipboard.setData(ClipboardData(text: formatted));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('FAQ copied to clipboard'),
        duration: const Duration(seconds: 2),
        backgroundColor: context.cardDark,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeProvider.of(context);
    final primary = theme.primary;
    final cardColor = context.cardDark;
    final textPrimary = context.textPrimary;
    final textMuted = context.textMuted;
    final border = context.outlineColor;
    final filtered = _filteredFaqs;

    return AppSubScreenScaffold(
      title: 'Frequently Asked Questions',
      children: [
        // ── HERO BANNER ───────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: border),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                primary.withValues(alpha: 0.12),
                cardColor,
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: primary.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      '06 · FAQ',
                      style: TextStyle(
                        color: primary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'OWNER\'S MANUAL',
                    style: TextStyle(
                      color: textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Frequently Asked Questions',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Clear answers on bit-perfect playback, Android audio routing, resampling, and DSP features.',
                style: TextStyle(
                  color: textMuted,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── SEARCH BAR ────────────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
          ),
          child: TextField(
            controller: _searchController,
            onChanged: (val) {
              setState(() {
                _searchQuery = val.trim();
              });
            },
            style: TextStyle(color: textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search questions, keywords (e.g. MMAP, 64-bit)...',
              hintStyle: TextStyle(color: textMuted.withValues(alpha: 0.7)),
              prefixIcon: Icon(Icons.search_rounded, color: primary, size: 22),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.close_rounded, color: textMuted, size: 20),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // ── CATEGORY FILTER CHIPS ─────────────────────────────────────────
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _categories.map((cat) {
              final isSelected = _selectedCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  label: Text(cat),
                  selected: isSelected,
                  onSelected: (_) {
                    setState(() {
                      _selectedCategory = cat;
                    });
                  },
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : textMuted,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                  selectedColor: primary,
                  backgroundColor: cardColor,
                  side: BorderSide(
                    color: isSelected ? primary : border,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  showCheckmark: false,
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 16),

        // ── FAQ LIST OR EMPTY STATE ───────────────────────────────────────
        if (filtered.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: border),
            ),
            child: Column(
              children: [
                Icon(Icons.search_off_rounded, color: textMuted, size: 48),
                const SizedBox(height: 16),
                Text(
                  'No matching questions found',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Try searching for another keyword or clear the filter.',
                  style: TextStyle(color: textMuted, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                      _selectedCategory = 'All';
                    });
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Reset filters'),
                  style: TextButton.styleFrom(foregroundColor: primary),
                ),
              ],
            ),
          )
        else
          ...filtered.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final isExpanded = _expandedIds.contains(item.id);

            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: _buildFaqCard(
                item: item,
                index: index + 1,
                isExpanded: isExpanded,
                primary: primary,
                cardColor: cardColor,
                textPrimary: textPrimary,
                textMuted: textMuted,
                border: border,
              ),
            );
          }),

        const SizedBox(height: 16),

        // ── FOOTER CARD ───────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.menu_book_rounded, color: primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'NEED MORE DETAILS?',
                    style: TextStyle(
                      color: textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Inspect the Full Manual & C++ Engine',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Explore the Sautiflow C++17 audio engine core, signal chain architecture, and build matrix on GitHub.',
                style: TextStyle(color: textMuted, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      final uri = Uri.parse('https://github.com/wambugu71/sautiflow');
                      try {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      } catch (_) {}
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('GitHub Source'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textPrimary,
                      side: BorderSide(color: border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final uri = Uri.parse('https://github.com/wambugu71/sautiflow/releases');
                      try {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      } catch (_) {}
                    },
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: const Text('Releases & Notes'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primary,
                      side: BorderSide(color: primary.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildFaqCard({
    required FaqItem item,
    required int index,
    required bool isExpanded,
    required Color primary,
    required Color cardColor,
    required Color textPrimary,
    required Color textMuted,
    required Color border,
  }) {
    final qNumber = index < 10 ? '0$index' : '$index';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: isExpanded ? primary.withValues(alpha: 0.05) : cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isExpanded ? primary.withValues(alpha: 0.5) : border,
          width: isExpanded ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _toggleExpand(item.id),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row: Category pill + Q number + Chevron
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border:
                          Border.all(color: primary.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      'Q$qNumber · ${item.category.toUpperCase()}',
                      style: TextStyle(
                        color: primary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: isExpanded ? primary : textMuted,
                      size: 22,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Question Title
              Text(
                item.question,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),

              // Expanded Answer Content
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    Divider(color: border, height: 1),
                    const SizedBox(height: 12),
                    _buildFormattedAnswer(
                      item.answer,
                      textPrimary,
                      textMuted,
                      primary,
                    ),
                    const SizedBox(height: 14),
                    // Action footer: Copy & Tags
                    Row(
                      children: [
                        Wrap(
                          spacing: 6,
                          children: item.tags.take(3).map((tag) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: context.cardDark,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: border),
                              ),
                              child: Text(
                                '#$tag',
                                style: TextStyle(
                                  color: textMuted,
                                  fontSize: 11,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(Icons.copy_rounded,
                              size: 18, color: textMuted),
                          tooltip: 'Copy FAQ',
                          onPressed: () => _copyToClipboard(item),
                        ),
                      ],
                    ),
                  ],
                ),
                crossFadeState: isExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 250),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormattedAnswer(
    String answer,
    Color textPrimary,
    Color textMuted,
    Color primary,
  ) {
    // Split into paragraphs
    final paragraphs = answer.split('\n\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: paragraphs.map((p) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Text(
            p,
            style: TextStyle(
              color: textPrimary.withValues(alpha: 0.9),
              fontSize: 14,
              height: 1.5,
            ),
          ),
        );
      }).toList(),
    );
  }
}
