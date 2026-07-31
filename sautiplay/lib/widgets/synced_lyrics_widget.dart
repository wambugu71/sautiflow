import 'package:flutter/material.dart';

class LrcLine {
  final Duration time;
  final String text;

  const LrcLine({required this.time, required this.text});
}

class LrcParser {
  static List<LrcLine> parse(String content) {
    final lines = <LrcLine>[];
    // Matches [mm:ss.xx] or [m:s.xx] or [mm:ss:xx] or [mm:ss]
    final regExp = RegExp(r'\[(\d+):(\d+)(?:[\.\:](\d+))?\]\s*(.*)');
    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final match = regExp.firstMatch(line);
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final subStr = match.group(3) ?? '0';
        int millis = 0;
        if (subStr.length == 1) {
          millis = int.parse(subStr) * 100;
        } else if (subStr.length == 2) {
          millis = int.parse(subStr) * 10;
        } else if (subStr.length >= 3) {
          millis = int.parse(subStr.substring(0, 3));
        }
        final dur = Duration(minutes: minutes, seconds: seconds, milliseconds: millis);
        final text = match.group(4)!.trim();
        if (text.isNotEmpty) {
          lines.add(LrcLine(time: dur, text: text));
        }
      }
    }
    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }
}

class SyncedLyricsWidget extends StatefulWidget {
  final String lyricsRaw;
  final Duration currentPosition;
  final ValueChanged<Duration>? onSeek;
  final double fontSize;
  final Color activeColor;
  final Color inactiveColor;

  const SyncedLyricsWidget({
    super.key,
    required this.lyricsRaw,
    required this.currentPosition,
    this.onSeek,
    this.fontSize = 15.0,
    this.activeColor = const Color(0xFF38BDF8),
    this.inactiveColor = Colors.white60,
  });

  @override
  State<SyncedLyricsWidget> createState() => _SyncedLyricsWidgetState();
}

class _SyncedLyricsWidgetState extends State<SyncedLyricsWidget> {
  final ScrollController _scrollController = ScrollController();
  List<LrcLine> _lines = [];
  int _lastActiveIndex = -1;

  @override
  void initState() {
    super.initState();
    _parseLyrics();
  }

  @override
  void didUpdateWidget(covariant SyncedLyricsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lyricsRaw != widget.lyricsRaw) {
      _parseLyrics();
    } else {
      _updateActiveIndex();
    }
  }

  void _parseLyrics() {
    _lines = LrcParser.parse(widget.lyricsRaw);
    _lastActiveIndex = -1;
    _updateActiveIndex();
  }

  void _updateActiveIndex() {
    if (_lines.isEmpty) return;
    int active = -1;
    final posMs = widget.currentPosition.inMilliseconds;
    for (int i = 0; i < _lines.length; i++) {
      if (posMs >= _lines[i].time.inMilliseconds) {
        active = i;
      } else {
        break;
      }
    }

    if (active != _lastActiveIndex) {
      _lastActiveIndex = active;
      if (active >= 0 && _scrollController.hasClients) {
        const double itemHeight = 44.0;
        final targetOffset = (active * itemHeight) - 80;
        _scrollController.animateTo(
          targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_lines.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Text(
              widget.lyricsRaw.isNotEmpty ? widget.lyricsRaw : 'No lyrics available',
              textAlign: TextAlign.center,
              style: TextStyle(color: widget.inactiveColor, fontSize: widget.fontSize, height: 1.5),
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      itemCount: _lines.length,
      itemBuilder: (context, index) {
        final line = _lines[index];
        final isActive = index == _lastActiveIndex;

        return GestureDetector(
          onTap: () {
            widget.onSeek?.call(line.time);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            alignment: Alignment.center,
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 250),
              style: TextStyle(
                fontSize: isActive ? widget.fontSize + 3.0 : widget.fontSize,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                color: isActive ? widget.activeColor : widget.inactiveColor,
                height: 1.4,
                shadows: isActive
                    ? [
                        Shadow(
                          color: widget.activeColor.withValues(alpha: 0.6),
                          blurRadius: 10,
                        ),
                      ]
                    : null,
              ),
              child: Text(
                line.text,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      },
    );
  }
}
