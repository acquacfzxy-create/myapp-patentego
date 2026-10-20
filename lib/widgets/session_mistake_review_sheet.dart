import 'package:flutter/material.dart';

import '../config/app_strings.dart';
import '../models/question.dart';
import '../services/explanation_parser.dart';
import 'explanation_emphasis.dart';
import 'question_widget.dart';

/// A snapshot of the first answer, independent of the current practice card.
class SessionMistake {
  const SessionMistake({required this.question, required this.selectedAnswer});

  final Question question;
  final bool selectedAnswer;
}

/// Full review is free. Reading never submits an answer or updates mastery.
class SessionMistakeReviewSheet extends StatefulWidget {
  const SessionMistakeReviewSheet({
    super.key,
    required this.mistakes,
    required this.language,
  }) : assert(mistakes.length > 0);

  final List<SessionMistake> mistakes;
  final String language;

  @override
  State<SessionMistakeReviewSheet> createState() =>
      _SessionMistakeReviewSheetState();
}

class _SessionMistakeReviewSheetState extends State<SessionMistakeReviewSheet> {
  final _scrollController = ScrollController();
  int _index = 0;
  final Set<String> _expandedQuestions = {};
  final _supplementKey = GlobalKey();

  String _text(String key) => AppStrings.getWithLanguage(widget.language, key);

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _move(int index) {
    setState(() => _index = index);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _toggleMore(Question question) {
    var expanded = false;
    setState(() {
      if (!_expandedQuestions.remove(question.id)) {
        _expandedQuestions.add(question.id);
        expanded = true;
      }
    });
    if (!expanded) return;
    // 展開後自動滑到補充解析，與做題時打開解析的體驗一致。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _supplementKey.currentContext;
      if (!mounted || target == null) return;
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: 0.05,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final mistake = widget.mistakes[_index];
    final question = mistake.question;
    final italian = question.getQuestionText('it') ??
        question.getQuestionText(widget.language) ??
        _text('question_content_missing');
    final translated = question.getQuestionText(widget.language);
    final explanation = question.getExplanationText(widget.language) ??
        question.getExplanationText('it') ??
        '';
    final parsed = ExplanationParser.parse(explanation);
    // A partial structured record must not expose raw JSON as the basic reason.
    final reason =
        parsed.isJsonFormat && parsed.detailedDescription == explanation
            ? ''
            : parsed.detailedDescription;
    final colors = Theme.of(context).colorScheme;
    final hasMore = parsed.isJsonFormat &&
        ((parsed.keyPoints?.any((point) =>
                    (point['title'] ?? '').trim().isNotEmpty ||
                    (point['content'] ?? '').trim().isNotEmpty) ??
                false) ||
            (parsed.studyTip?.trim().isNotEmpty ?? false));
    final isExpanded = _expandedQuestions.contains(question.id);

    return FractionallySizedBox(
      heightFactor: 0.9,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _text('session_mistakes_title'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Text('${_index + 1}/${widget.mistakes.length}',
                    key: const Key('session_review_position')),
                CloseButton(key: const Key('session_review_close')),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(italian,
                      key: const Key('session_review_question'),
                      style: Theme.of(context).textTheme.titleMedium),
                  if (question.imageName?.isNotEmpty == true) ...[
                    const SizedBox(height: 16),
                    _image(question.imageName!),
                  ],
                  if (widget.language != 'it' &&
                      translated != null &&
                      translated != italian) ...[
                    const SizedBox(height: 16),
                    Text(translated),
                  ],
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      Text(
                        '${_text('web_your_answer')}: '
                        '${mistake.selectedAnswer ? 'Vero' : 'Falso'}',
                        style: TextStyle(color: colors.error),
                      ),
                      Text(
                        '${_text('modal_correct_answer_label')}: '
                        '${question.answer ? 'Vero' : 'Falso'}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_text('session_mistakes_reason'),
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        reason.trim().isEmpty
                            ? Text(_text('explanation_missing_short'))
                            : Text.rich(ExplanationEmphasis.build(
                                context,
                                reason,
                                base: DefaultTextStyle.of(context).style,
                              )),
                      ],
                    ),
                  ),
                  if (hasMore) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      key: const Key('session_review_more'),
                      onPressed: () => _toggleMore(question),
                      icon: Icon(
                          isExpanded ? Icons.expand_less : Icons.expand_more),
                      label: Text(_text(isExpanded
                          ? 'session_mistakes_collapse'
                          : 'session_mistakes_expand')),
                    ),
                    if (isExpanded)
                      KeyedSubtree(
                        key: _supplementKey,
                        child: QuestionWidget.buildExplanationSupplement(
                          context,
                          parsedExplanation: parsed,
                          currentLanguage: widget.language,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  if (_index > 0)
                    IconButton.outlined(
                      key: const Key('session_review_previous'),
                      tooltip: _text('previous_question'),
                      onPressed: () => _move(_index - 1),
                      icon: const Icon(Icons.navigate_before),
                    ),
                  const Spacer(),
                  if (_index + 1 < widget.mistakes.length)
                    IconButton.filled(
                      key: const Key('session_review_next'),
                      tooltip: _text('next_question'),
                      onPressed: () => _move(_index + 1),
                      icon: const Icon(Icons.navigate_next),
                    )
                  else
                    IconButton.filled(
                      key: const Key('session_review_done'),
                      tooltip: _text('session_mistakes_done'),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.check),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _image(String path) {
    Widget error(BuildContext context, Object error, StackTrace? stack) =>
        const Icon(Icons.image_not_supported_outlined);
    final isRemote = path.startsWith('https://') || path.startsWith('http://');
    var assetPath = path.startsWith('/') ? path.substring(1) : path;
    if (assetPath.startsWith('img_sign/')) assetPath = 'images/$assetPath';
    return SizedBox(
      height: 200,
      child: isRemote
          ? Image.network(path, fit: BoxFit.contain, errorBuilder: error)
          : Image.asset(assetPath, fit: BoxFit.contain, errorBuilder: error),
    );
  }
}
