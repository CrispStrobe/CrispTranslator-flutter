// lib/pages/settings_page.dart
import 'package:flutter/material.dart';
import '../models/app_settings.dart';

class SettingsPage extends StatefulWidget {
  final AppSettings settings;
  final Function(AppSettings) onSettingsChanged;
  
  const SettingsPage({
    Key? key,
    required this.settings,
    required this.onSettingsChanged,
  }) : super(key: key);
  
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late AppSettings _settings;
  
  @override
  void initState() {
    super.initState();
    _settings = AppSettings(
      beamSize: widget.settings.beamSize,
      repetitionPenalty: widget.settings.repetitionPenalty,
      noRepeatNgramSize: widget.settings.noRepeatNgramSize,
      maxLength: widget.settings.maxLength,
      showAlignments: widget.settings.showAlignments,
      verboseLogging: widget.settings.verboseLogging,
      preserveFormatting: widget.settings.preserveFormatting,
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Translation Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Quality Presets
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quality Presets',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _applyPreset(AppSettings.speed()),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: !_settings.useBeamSearch ? Colors.blue.shade50 : null,
                          ),
                          child: const Column(
                            children: [
                              Icon(Icons.speed),
                              SizedBox(height: 4),
                              Text('Speed'),
                              Text('Greedy', style: TextStyle(fontSize: 10)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _applyPreset(AppSettings.balanced()),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: (_settings.useBeamSearch && _settings.beamSize == 2) 
                                ? Colors.blue.shade50 : null,
                          ),
                          child: const Column(
                            children: [
                              Icon(Icons.balance),
                              SizedBox(height: 4),
                              Text('Balanced'),
                              Text('2 Beams', style: TextStyle(fontSize: 10)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _applyPreset(AppSettings.quality()),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: (_settings.useBeamSearch && _settings.beamSize == 4) 
                                ? Colors.blue.shade50 : null,
                          ),
                          child: const Column(
                            children: [
                              Icon(Icons.high_quality),
                              SizedBox(height: 4),
                              Text('Quality'),
                              Text('4 Beams', style: TextStyle(fontSize: 10)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // 2. Performance Settings
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Performance',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),

                  // Beam Search Master Toggle
                  SwitchListTile(
                    title: const Text('Use Beam Search'),
                    subtitle: const Text('Explores multiple translation paths for higher accuracy'),
                    value: _settings.useBeamSearch,
                    onChanged: (value) {
                      setState(() {
                        _settings.useBeamSearch = value;
                        // If turning on, default to at least 2 beams; if off, set to 1 (Greedy)
                        if (value && _settings.beamSize < 2) _settings.beamSize = 2;
                        if (!value) _settings.beamSize = 1;
                      });
                    },
                  ),
                  
                  const Divider(),
                  
                  // Contextual Beam Size Slider
                  if (_settings.useBeamSearch)
                    _buildSlider(
                      'Beam Size',
                      '${_settings.beamSize}',
                      _settings.beamSize.toDouble(),
                      2, 4,
                      (value) => setState(() => _settings.beamSize = value.toInt()),
                      subtitle: 'Higher values improve quality but increase latency',
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                      child: Text(
                        'Currently using Greedy Search (Fastest)',
                        style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                      ),
                    ),
                  
                  _buildSlider(
                    'Repetition Penalty',
                    _settings.repetitionPenalty.toStringAsFixed(1),
                    _settings.repetitionPenalty,
                    1.0, 2.0,
                    (value) => setState(() => _settings.repetitionPenalty = value),
                    subtitle: 'Prevents repetitive outputs',
                  ),
                  
                  _buildSlider(
                    'N-gram Blocking',
                    '${_settings.noRepeatNgramSize}',
                    _settings.noRepeatNgramSize.toDouble(),
                    1, 5,
                    (value) => setState(() => _settings.noRepeatNgramSize = value.toInt()),
                    subtitle: 'Blocks repeated ${_settings.noRepeatNgramSize}-grams',
                  ),
                  
                  _buildSlider(
                    'Max Length',
                    '${_settings.maxLength}',
                    _settings.maxLength.toDouble(),
                    64, 512,
                    (value) => setState(() => _settings.maxLength = value.toInt()),
                    subtitle: 'Maximum output tokens',
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // 3. UI/Display Settings
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Display',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  
                  SwitchListTile(
                    title: const Text('Show Alignments'),
                    subtitle: const Text('Display word-to-word mappings'),
                    value: _settings.showAlignments,
                    onChanged: (value) => setState(() => _settings.showAlignments = value),
                  ),
                  
                  SwitchListTile(
                    title: const Text('Verbose Logging'),
                    subtitle: const Text('Detailed console output'),
                    value: _settings.verboseLogging,
                    onChanged: (value) => setState(() => _settings.verboseLogging = value),
                  ),
                  
                  SwitchListTile(
                    title: const Text('Preserve Formatting'),
                    subtitle: const Text('Keep fonts, styles, and layout'),
                    value: _settings.preserveFormatting,
                    onChanged: (value) => setState(() => _settings.preserveFormatting = value),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Save button
          ElevatedButton.icon(
            onPressed: () {
              widget.onSettingsChanged(_settings);
              Navigator.pop(context);
            },
            icon: const Icon(Icons.save),
            label: const Text('Save Settings'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.all(16),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSlider(
    String title,
    String value,
    double currentValue,
    double min,
    double max,
    Function(double) onChanged,
    {String? subtitle}
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(value, style: const TextStyle(color: Colors.blue)),
          ],
        ),
        if (subtitle != null)
          Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Slider(
          value: currentValue,
          min: min,
          max: max,
          divisions: max == 4 ? 3 : (max == 5 ? 4 : 100),
          onChanged: onChanged,
        ),
      ],
    );
  }
  
  void _applyPreset(AppSettings preset) {
    setState(() => _settings = preset);
    widget.onSettingsChanged(preset);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Preset applied!')),
    );
  }
}