import 'package:flutter/material.dart';

typedef TtsRecordingAction = Future<String?> Function(
  TtsRecordingRequest request,
);

@immutable
class TtsRecordingRequest {
  const TtsRecordingRequest({
    required this.title,
    required this.text,
    required this.language,
    required this.voice,
    required this.speed,
  });

  final String title;
  final String text;
  final String language;
  final String voice;
  final double speed;
}

enum _EditorAction { top, bottom, clear, settings }

class TtsStudioScreen extends StatefulWidget {
  const TtsStudioScreen({
    super.key,
    required this.onPlayNow,
    required this.onSaveForLater,
  });

  final TtsRecordingAction onPlayNow;
  final TtsRecordingAction onSaveForLater;

  @override
  State<TtsStudioScreen> createState() => _TtsStudioScreenState();
}

class _TtsStudioScreenState extends State<TtsStudioScreen> {
  static const _maxCharacters = 500000;
  static const _voices = <String, List<(String, String)>>{
    'en': [
      ('af_heart', 'American · Heart'),
      ('af_bella', 'American · Bella'),
      ('af_sarah', 'American · Sarah'),
      ('af_nicole', 'American · Nicole'),
      ('am_michael', 'American · Michael'),
      ('am_adam', 'American · Adam'),
      ('bf_emma', 'British · Emma'),
      ('bm_george', 'British · George'),
    ],
    'fr': [('ff_siwis', 'French · Siwis')],
  };

  final _titleController = TextEditingController();
  final _textController = TextEditingController();
  final _searchController = TextEditingController();
  final _editorScrollController = ScrollController();
  final _editorFocusNode = FocusNode();
  String _language = 'en';
  String _voice = 'af_heart';
  double _speed = 1;
  bool _showSearch = false;
  bool _working = false;
  String? _error;
  String? _message;
  String _searchMessage = '';

  @override
  void dispose() {
    _titleController.dispose();
    _textController.dispose();
    _searchController.dispose();
    _editorScrollController.dispose();
    _editorFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool playNow}) async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Add the text you want to turn into audio.');
      return;
    }
    if (text.length > _maxCharacters) {
      setState(() => _error = 'Keep the text under 500,000 characters.');
      return;
    }

    final request = TtsRecordingRequest(
      title: _titleController.text.trim().isEmpty
          ? 'Voice recording'
          : _titleController.text.trim(),
      text: text,
      language: _language,
      voice: _voice,
      speed: _speed,
    );
    setState(() {
      _working = true;
      _error = null;
      _message = null;
    });
    try {
      final error = await (playNow ? widget.onPlayNow : widget.onSaveForLater)(
        request,
      );
      if (!mounted) return;
      setState(() {
        _error = error;
        _message = error == null
            ? playNow
                  ? 'Playback started. The recording is also being saved.'
                  : 'Queued for background generation. You can leave this screen.'
            : null;
      });
    } catch (error) {
      if (mounted)
        setState(() => _error = 'Could not start the recording: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _moveToMatch({required bool forward}) {
    final query = _searchController.text.toLowerCase();
    final source = _textController.text.toLowerCase();
    if (query.isEmpty || source.isEmpty) {
      setState(() => _searchMessage = 'Enter text to search for.');
      return;
    }

    final selection = _textController.selection;
    final cursor = forward
        ? (selection.extentOffset < 0 ? 0 : selection.extentOffset)
        : (selection.baseOffset < 0 ? 0 : selection.baseOffset);
    var match = forward
        ? source.indexOf(query, cursor)
        : cursor == 0
        ? -1
        : source.lastIndexOf(query, cursor - 1);
    if (match < 0) {
      match = forward ? source.indexOf(query) : source.lastIndexOf(query);
    }
    if (match < 0) {
      setState(() => _searchMessage = 'No matches.');
      return;
    }

    _textController.selection = TextSelection(
      baseOffset: match,
      extentOffset: match + query.length,
    );
    _editorFocusNode.requestFocus();
    setState(() => _searchMessage = 'Found at character ${match + 1}');
  }

  void _jumpToTop() {
    if (_editorScrollController.hasClients) {
      _editorScrollController.animateTo(
        _editorScrollController.position.minScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  void _jumpToBottom() {
    if (_editorScrollController.hasClients) {
      _editorScrollController.animateTo(
        _editorScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _clearAll() async {
    if (_textController.text.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all text?'),
        content: const Text('This clears the text in the editor.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _textController.clear();
      setState(() {
        _error = null;
        _message = null;
        _searchMessage = '';
      });
    }
  }

  Future<void> _showSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Voice settings',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _language,
                  decoration: const InputDecoration(labelText: 'Language'),
                  items: const [
                    DropdownMenuItem(value: 'en', child: Text('English')),
                    DropdownMenuItem(value: 'fr', child: Text('French')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _language = value;
                      _voice = _voices[value]!.first.$1;
                    });
                    setSheetState(() {});
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey('studio-voice-$_voice'),
                  initialValue: _voice,
                  decoration: const InputDecoration(labelText: 'Voice'),
                  items: _voices[_language]!
                      .map(
                        (voice) => DropdownMenuItem(
                          value: voice.$1,
                          child: Text(voice.$2),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _voice = value);
                      setSheetState(() {});
                    }
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.speed_rounded),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('Speaking speed')),
                    Text('${_speed.toStringAsFixed(1)}×'),
                  ],
                ),
                Slider(
                  value: _speed,
                  min: 0.8,
                  max: 1.2,
                  divisions: 8,
                  onChanged: (value) {
                    setState(() => _speed = value);
                    setSheetState(() {});
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audiobook studio'),
        actions: [
          IconButton(
            tooltip: _showSearch ? 'Close search' : 'Search text',
            onPressed: () => setState(() {
              _showSearch = !_showSearch;
              _searchMessage = '';
            }),
            icon: Icon(
              _showSearch ? Icons.search_off_rounded : Icons.search_rounded,
            ),
          ),
          PopupMenuButton<_EditorAction>(
            tooltip: 'Editor actions',
            onSelected: (action) {
              switch (action) {
                case _EditorAction.top:
                  _jumpToTop();
                  break;
                case _EditorAction.bottom:
                  _jumpToBottom();
                  break;
                case _EditorAction.clear:
                  _clearAll();
                  break;
                case _EditorAction.settings:
                  _showSettings();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _EditorAction.top,
                child: ListTile(
                  leading: Icon(Icons.vertical_align_top),
                  title: Text('Go to top'),
                ),
              ),
              PopupMenuItem(
                value: _EditorAction.bottom,
                child: ListTile(
                  leading: Icon(Icons.vertical_align_bottom),
                  title: Text('Go to bottom'),
                ),
              ),
              PopupMenuItem(
                value: _EditorAction.clear,
                child: ListTile(
                  leading: Icon(Icons.delete_sweep_outlined),
                  title: Text('Delete all text'),
                ),
              ),
              PopupMenuItem(
                value: _EditorAction.settings,
                child: ListTile(
                  leading: Icon(Icons.tune_rounded),
                  title: Text('Voice settings'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _titleController,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 160,
                decoration: const InputDecoration(
                  labelText: 'Recording title',
                  hintText: 'e.g. A note for later',
                  prefixIcon: Icon(Icons.title_rounded),
                ),
              ),
            ),
            if (_showSearch)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _moveToMatch(forward: true),
                        decoration: InputDecoration(
                          hintText: 'Find in text',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixText: _searchMessage,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Previous match',
                      onPressed: () => _moveToMatch(forward: false),
                      icon: const Icon(Icons.keyboard_arrow_up_rounded),
                    ),
                    IconButton(
                      tooltip: 'Next match',
                      onPressed: () => _moveToMatch(forward: true),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                child: TextField(
                  controller: _textController,
                  focusNode: _editorFocusNode,
                  scrollController: _editorScrollController,
                  expands: true,
                  minLines: null,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  textAlignVertical: TextAlignVertical.top,
                  onChanged: (_) {
                    if (_error != null || _message != null) {
                      setState(() {
                        _error = null;
                        _message = null;
                      });
                    }
                  },
                  decoration: InputDecoration(
                    hintText:
                        'Paste or write a long text in English or French...',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    contentPadding: const EdgeInsets.all(16),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
              child: Row(
                children: [
                  Expanded(
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _textController,
                      builder: (context, value, _) => Text(
                        '${value.text.length} / $_maxCharacters characters',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Go to top',
                    onPressed: _jumpToTop,
                    icon: const Icon(Icons.vertical_align_top_rounded),
                  ),
                  IconButton(
                    tooltip: 'Go to bottom',
                    onPressed: _jumpToBottom,
                    icon: const Icon(Icons.vertical_align_bottom_rounded),
                  ),
                  IconButton(
                    tooltip: 'Voice settings',
                    onPressed: _showSettings,
                    icon: const Icon(Icons.tune_rounded),
                  ),
                ],
              ),
            ),
            if (_error != null || _message != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 4,
                ),
                child: Text(
                  _error ?? _message!,
                  style: TextStyle(
                    color: _error == null ? colors.primary : colors.error,
                  ),
                ),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _working
                            ? null
                            : () => _submit(playNow: false),
                        icon: _working
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.bookmark_add_outlined),
                        label: const Text('Save for later'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _working
                            ? null
                            : () => _submit(playNow: true),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Play now'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
