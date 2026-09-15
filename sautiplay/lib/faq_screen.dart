import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

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
    final categories =
        sautiplayFaqItems.map((e) => e.category).toSet().toList();
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
        final inTags =
            item.tags.any((tag) => tag.toLowerCase().contains(query));
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
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            //const SizedBox(height: 12),
            Text(
              'FAQ\'s',
              style: TextStyle(
                color: textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 8),
          ],
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
              hintText: 'Search questions...',
              hintStyle: TextStyle(color: textMuted.withValues(alpha: 0.7)),
              prefixIcon: Icon(Icons.search_rounded, color: primary, size: 22),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon:
                          Icon(Icons.close_rounded, color: textMuted, size: 20),
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
          M3ECardList(
            key: ValueKey('faq_${_selectedCategory}_$_searchQuery'),
            itemCount: filtered.length,
            color: cardColor,
            outerRadius: 16,
            innerRadius: 6,
            gap: 3,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            haptic: M3EHapticFeedback.light,
            onTap: (index) => _toggleExpand(filtered[index].id),
            itemBuilder: (context, index) {
              final item = filtered[index];
              final isExpanded = _expandedIds.contains(item.id);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Row: Question (up to 2 lines) + Animated Chevron
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          item.question,
                          maxLines: 2,
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOutCubicEmphasized,
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: isExpanded ? primary : textMuted,
                          size: 20,
                        ),
                      ),
                    ],
                  ),

                  AnimatedCrossFade(
                    firstChild: const SizedBox.shrink(),
                    secondChild: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        Divider(color: border, height: 1),
                        const SizedBox(height: 8),
                        _buildFormattedAnswer(
                          item.answer,
                          textPrimary,
                          textMuted,
                          primary,
                        ),
                        const SizedBox(height: 8),
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
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => _copyToClipboard(item),
                            ),
                          ],
                        ),
                      ],
                    ),
                    crossFadeState: isExpanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 300),
                    sizeCurve: Curves.easeInOutCubicEmphasized,
                  ),
                ],
              );
            },
          ),

        const SizedBox(height: 12),
      ],
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
          padding: const EdgeInsets.only(bottom: 6.0),
          child: Text(
            p,
            style: TextStyle(
              color: textPrimary.withValues(alpha: 0.9),
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
        );
      }).toList(),
    );
  }
}
