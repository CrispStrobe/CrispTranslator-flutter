// lib/widgets/alignment_visualizer.dart
import 'package:flutter/material.dart';
// Use alias to avoid conflict with Flutter's Alignment
import '../services/docx_translator.dart' as docx;

class AlignmentVisualizer extends StatelessWidget {
  final String sourceText;
  final String targetText;
  final List<docx.Alignment> alignments; // Use aliased type
  final bool showLines;
  
  const AlignmentVisualizer({
    Key? key,
    required this.sourceText,
    required this.targetText,
    required this.alignments,
    this.showLines = true,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    final sourceWords = sourceText.split(RegExp(r'\s+'));
    final targetWords = targetText.split(RegExp(r'\s+'));
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Word Alignments (${alignments.length} links)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            
            _buildWordRow(
              context,
              sourceWords,
              alignments.map((a) => a.sourceIndex).toSet(), // Fixed
              isSource: true,
            ),
            
            const SizedBox(height: 8),
            
            if (showLines && alignments.isNotEmpty)
              CustomPaint(
                size: Size(double.infinity, 40),
                painter: _AlignmentPainter(
                  alignments: alignments,
                  sourceWordCount: sourceWords.length,
                  targetWordCount: targetWords.length,
                ),
              ),
            
            const SizedBox(height: 8),
            
            _buildWordRow(
              context,
              targetWords,
              alignments.map((a) => a.targetIndex).toSet(), // Fixed
              isSource: false,
            ),
            
            const SizedBox(height: 16),
            
            ExpansionTile(
              title: const Text('Alignment Details'),
              children: [
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: alignments.length,
                    itemBuilder: (context, index) {
                      final link = alignments[index];
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 12,
                          child: Text('${index + 1}'),
                        ),
                        title: Text(
                          '${sourceWords[link.sourceIndex]} ↔ ${targetWords[link.targetIndex]}',
                        ),
                        subtitle: Text('Indices: ${link.sourceIndex} → ${link.targetIndex}'),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildWordRow(
    BuildContext context,
    List<String> words,
    Set<int> highlightedIndices,
    {required bool isSource}
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: List.generate(words.length, (index) {
        final isHighlighted = highlightedIndices.contains(index);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isHighlighted
                ? (isSource ? Colors.blue.shade100 : Colors.green.shade100)
                : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(4),
            border: isHighlighted
                ? Border.all(
                    color: isSource ? Colors.blue : Colors.green,
                    width: 2,
                  )
                : null,
          ),
          child: Text(
            words[index],
            style: TextStyle(
              fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
              color: isHighlighted ? Colors.black87 : Colors.black54,
            ),
          ),
        );
      }),
    );
  }
}

class _AlignmentPainter extends CustomPainter {
  final List<docx.Alignment> alignments; // Use aliased type
  final int sourceWordCount;
  final int targetWordCount;
  
  _AlignmentPainter({
    required this.alignments,
    required this.sourceWordCount,
    required this.targetWordCount,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
    ];
    
    for (int i = 0; i < alignments.length; i++) {
      final link = alignments[i];
      paint.color = colors[i % colors.length].withOpacity(0.6);
      
      final sourceX = (link.sourceIndex / sourceWordCount) * size.width;
      final targetX = (link.targetIndex / targetWordCount) * size.width;
      
      final path = Path();
      path.moveTo(sourceX, 0);
      path.quadraticBezierTo(
        (sourceX + targetX) / 2,
        size.height / 2,
        targetX,
        size.height,
      );
      
      canvas.drawPath(path, paint);
    }
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}