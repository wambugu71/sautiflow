import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_m3shapes_extended/flutter_m3shapes_extended.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

import '../services/app_theme_service.dart';

/// Metadata definition for each M3E expressive shape option.
class M3EShapeItem {
  final Shapes shape;
  final String name;
  final String category;
  final bool isCurated;

  const M3EShapeItem({
    required this.shape,
    required this.name,
    required this.category,
    this.isCurated = false,
  });
}

/// Comprehensive catalog of all 35 Material 3 Expressive shapes.
const List<M3EShapeItem> kM3EAlbumArtShapes = [
  // ── Curated & Popular ──────────────────────────────────────────────────────
  M3EShapeItem(
    shape: Shapes.bun,
    name: 'Bun (Default)',
    category: 'Curated',
    isCurated: true,
  ),
  M3EShapeItem(
    shape: Shapes.c4SidedCookie,
    name: '4-Sided Cookie',
    category: 'Curated',
    isCurated: true,
  ),
  M3EShapeItem(
    shape: Shapes.gem,
    name: 'Gem',
    category: 'Curated',
    isCurated: true,
  ),
  M3EShapeItem(
    shape: Shapes.slanted,
    name: 'Slanted',
    category: 'Curated',
    isCurated: true,
  ),
  M3EShapeItem(
    shape: Shapes.flower,
    name: 'Flower',
    category: 'Curated',
    isCurated: true,
  ),
  M3EShapeItem(
    shape: Shapes.heart,
    name: 'Heart',
    category: 'Curated',
    isCurated: true,
  ),
  M3EShapeItem(
    shape: Shapes.softBurst,
    name: 'Soft Burst',
    category: 'Curated',
    isCurated: true,
  ),
  M3EShapeItem(
    shape: Shapes.diamond,
    name: 'Diamond',
    category: 'Curated',
    isCurated: true,
  ),
  M3EShapeItem(
    shape: Shapes.circle,
    name: 'Circle',
    category: 'Geometric',
    isCurated: true,
  ),
  M3EShapeItem(
    shape: Shapes.pill,
    name: 'Pill',
    category: 'Curated',
    isCurated: true,
  ),
  M3EShapeItem(
    shape: Shapes.arch,
    name: 'Arch',
    category: 'Curated',
    isCurated: true,
  ),

  // ── Expressive & Playful ───────────────────────────────────────────────────
  M3EShapeItem(
    shape: Shapes.sunny,
    name: 'Sunny',
    category: 'Expressive',
  ),
  M3EShapeItem(
    shape: Shapes.verySunny,
    name: 'Very Sunny',
    category: 'Expressive',
  ),
  M3EShapeItem(
    shape: Shapes.burst,
    name: 'Star Burst',
    category: 'Expressive',
  ),
  M3EShapeItem(
    shape: Shapes.boom,
    name: 'Boom',
    category: 'Expressive',
  ),
  M3EShapeItem(
    shape: Shapes.softBoom,
    name: 'Soft Boom',
    category: 'Expressive',
  ),
  M3EShapeItem(
    shape: Shapes.l4LeafClover,
    name: '4-Leaf Clover',
    category: 'Expressive',
  ),
  M3EShapeItem(
    shape: Shapes.l8LeafClover,
    name: '8-Leaf Clover',
    category: 'Expressive',
  ),
  M3EShapeItem(
    shape: Shapes.puffy,
    name: 'Puffy Cloud',
    category: 'Expressive',
  ),
  M3EShapeItem(
    shape: Shapes.puffyDiamond,
    name: 'Puffy Diamond',
    category: 'Expressive',
  ),
  M3EShapeItem(
    shape: Shapes.ghostish,
    name: 'Ghostish',
    category: 'Expressive',
  ),
  M3EShapeItem(
    shape: Shapes.pixelCircle,
    name: 'Pixel Circle',
    category: 'Expressive',
  ),
  M3EShapeItem(
    shape: Shapes.pixelTriangle,
    name: 'Pixel Triangle',
    category: 'Expressive',
  ),

  // ── Multi-Sided Cookies ────────────────────────────────────────────────────
  M3EShapeItem(
    shape: Shapes.c6SidedCookie,
    name: '6-Sided Cookie',
    category: 'Expressive',
  ),
  M3EShapeItem(
    shape: Shapes.c7SidedCookie,
    name: '7-Sided Cookie',
    category: 'Expressive',
  ),
  M3EShapeItem(
    shape: Shapes.c9SidedCookie,
    name: '9-Sided Cookie',
    category: 'Expressive',
  ),
  M3EShapeItem(
    shape: Shapes.c12SidedCookie,
    name: '12-Sided Cookie',
    category: 'Expressive',
  ),

  // ── Geometric & Classic ────────────────────────────────────────────────────
  M3EShapeItem(
    shape: Shapes.square,
    name: 'Square',
    category: 'Geometric',
  ),
  M3EShapeItem(
    shape: Shapes.semicircle,
    name: 'Semicircle',
    category: 'Geometric',
  ),
  M3EShapeItem(
    shape: Shapes.oval,
    name: 'Oval',
    category: 'Geometric',
  ),
  M3EShapeItem(
    shape: Shapes.pentagon,
    name: 'Pentagon',
    category: 'Geometric',
  ),
  M3EShapeItem(
    shape: Shapes.triangle,
    name: 'Triangle',
    category: 'Geometric',
  ),
  M3EShapeItem(
    shape: Shapes.arrow,
    name: 'Arrow',
    category: 'Geometric',
  ),
  M3EShapeItem(
    shape: Shapes.fan,
    name: 'Fan',
    category: 'Geometric',
  ),
  M3EShapeItem(
    shape: Shapes.clampShell,
    name: 'Clamshell',
    category: 'Geometric',
  ),
];

/// Interactive Material 3 Expressive Album Art Shape Selector.
/// Features a live animated shape preview container and filtered shape catalog.
class AlbumArtShapeSelector extends StatefulWidget {
  final Uint8List? sampleAlbumArt;
  final bool showLivePreview;
  final ValueChanged<Shapes>? onShapeSelected;

  const AlbumArtShapeSelector({
    super.key,
    this.sampleAlbumArt,
    this.showLivePreview = true,
    this.onShapeSelected,
  });

  @override
  State<AlbumArtShapeSelector> createState() => _AlbumArtShapeSelectorState();
}

class _AlbumArtShapeSelectorState extends State<AlbumArtShapeSelector> {
  late Shapes _selectedShape;
  String _selectedCategory = 'Curated';

  final List<String> _categories = [
    'Curated',
    'All',
    'Expressive',
    'Geometric'
  ];

  @override
  void initState() {
    super.initState();
    _selectedShape = AppThemeService.instance.albumArtShape;
  }

  List<M3EShapeItem> get _filteredShapes {
    if (_selectedCategory == 'All') return kM3EAlbumArtShapes;
    if (_selectedCategory == 'Curated') {
      return kM3EAlbumArtShapes.where((s) => s.isCurated).toList();
    }
    return kM3EAlbumArtShapes
        .where((s) => s.category == _selectedCategory)
        .toList();
  }

  void _selectShape(Shapes shape) {
    setState(() {
      _selectedShape = shape;
    });
    AppThemeService.instance.saveAlbumArtShape(shape);
    widget.onShapeSelected?.call(shape);
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeProvider.of(context);
    final primary = theme.primary;
    final cardColor = theme.cardDark;
    final textDark = theme.textDark;
    final isDark = theme.bgDark.computeLuminance() < 0.15;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1A2E);

    final selectedItem = kM3EAlbumArtShapes.firstWhere(
      (s) => s.shape == _selectedShape,
      orElse: () => kM3EAlbumArtShapes.first,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        /*   // ── LIVE PREVIEW CONTAINER ──────────────────────────────────────────
        if (widget.showLivePreview) ...[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: context.outlineColor),
              boxShadow: [
                BoxShadow(
                  color: primary.withValues(alpha: 0.12),
                  blurRadius: 20,
                  spreadRadius: 2,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: primary.withAlpha(25),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.auto_awesome_rounded,
                          color: primary, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'LIVE SHAPE PREVIEW',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              color: primary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            selectedItem.name,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: primary.withAlpha(25),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: primary.withAlpha(60)),
                      ),
                      child: Text(
                        'M3E Morph',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // The Preview Shape Container
                Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeInBack,
                    transitionBuilder: (child, anim) => ScaleTransition(
                      scale: anim,
                      child: child,
                    ),
                    child: M3EContainer(
                      _selectedShape,
                      key: ValueKey(_selectedShape),
                      width: 140,
                      height: 140,
                      color: const Color(0xFF18232E),
                      clipBehavior: Clip.antiAlias,
                      boxShadow: [
                        BoxShadow(
                          color: primary.withValues(alpha: 0.4),
                          blurRadius: 28,
                          spreadRadius: 2,
                          offset: const Offset(0, 6),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                      child: widget.sampleAlbumArt != null &&
                              widget.sampleAlbumArt!.isNotEmpty
                          ? Image.memory(
                              widget.sampleAlbumArt!,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    primary.withValues(alpha: 0.7),
                                    const Color(0xFF101922),
                                  ],
                                ),
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.music_note_rounded,
                                  size: 56,
                                  color: Colors.white.withValues(alpha: 0.9),
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Now Playing screen album art will adapt to this expressive shape.',
                  style: TextStyle(
                    fontSize: 12,
                    color: textDark,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

      */
        // ── CATEGORY FILTER CHIPS ───────────────────────────────────────────
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: _categories.map((cat) {
              final isSelected = _selectedCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: M3EChip(
                  label: cat,
                  type: M3EChipType.filter,
                  selected: isSelected,
                  onPressed: () {
                    setState(() {
                      _selectedCategory = cat;
                    });
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 14),

        // ── SHAPES GRID / CAROUSEL ──────────────────────────────────────────
        SizedBox(
          height: 110,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _filteredShapes.length,
            itemBuilder: (context, index) {
              final item = _filteredShapes[index];
              final isActive = _selectedShape == item.shape;

              return GestureDetector(
                onTap: () => _selectShape(item.shape),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  width: 86,
                  margin: const EdgeInsets.only(right: 10, bottom: 6),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isActive ? primary.withAlpha(30) : cardColor,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isActive ? primary : context.outlineColor,
                      width: isActive ? 2.2 : 1.0,
                    ),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: primary.withAlpha(70),
                              blurRadius: 10,
                              spreadRadius: 1,
                            )
                          ]
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Miniature M3E Container
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          M3EContainer(
                            item.shape,
                            width: 44,
                            height: 44,
                            color: isActive
                                ? primary
                                : primary.withValues(alpha: 0.2),
                            border: BorderSide(
                              color: isActive
                                  ? Colors.white
                                  : primary.withValues(alpha: 0.5),
                              width: 1.2,
                            ),
                            child: Center(
                              child: Icon(
                                Icons.music_note_rounded,
                                size: 20,
                                color: isActive
                                    ? Colors.white
                                    : primary.withValues(alpha: 0.9),
                              ),
                            ),
                          ),
                          if (isActive)
                            Positioned(
                              right: -2,
                              top: -2,
                              child: Container(
                                width: 15,
                                height: 15,
                                decoration: BoxDecoration(
                                  color: primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Colors.white, width: 1.5),
                                ),
                                child: const Icon(
                                  Icons.check,
                                  size: 9,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.name,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight:
                              isActive ? FontWeight.bold : FontWeight.w500,
                          color: isActive ? primary : textDark,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Modal Bottom Sheet helper to show the Album Art Shape Picker.
class AlbumArtShapePickerSheet {
  static Future<Shapes?> show(
    BuildContext context, {
    Uint8List? sampleAlbumArt,
  }) async {
    return M3EBottomSheet.show<Shapes>(
      context,
      builder: (sheetCtx) {
        return Material(
          color: const Color(0xFF18232E),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppThemeService.instance.currentData.primary
                                .withAlpha(30),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.crop_original_rounded,
                            color: AppThemeService.instance.currentData.primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ALBUM ART CONTAINER SHAPE',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                  color: AppThemeService
                                      .instance.currentData.primary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Select M3E Shape',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded,
                              color: Colors.white70),
                          onPressed: () => Navigator.of(sheetCtx).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    AlbumArtShapeSelector(
                      sampleAlbumArt: sampleAlbumArt,
                      showLivePreview: true,
                      onShapeSelected: (shape) {
                        // Keep open for live tweaking or user can close when ready
                      },
                    ),
                    const SizedBox(height: 16),
                    M3EButton(
                      //   style: M3EButtonStyle.filled,
                      onPressed: () => Navigator.of(sheetCtx).pop(),
                      child: const Center(
                        child: Text(
                          'Done',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
