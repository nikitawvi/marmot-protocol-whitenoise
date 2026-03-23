import 'dart:math' show max, min;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:whitenoise/hooks/use_chat_messages.dart' show ChatMessageQuoteData;
import 'package:whitenoise/l10n/l10n.dart';
import 'package:whitenoise/src/rust/api/messages.dart' show ChatMessage;
import 'package:whitenoise/theme.dart';
import 'package:whitenoise/utils/bubble_grouping.dart' show shouldShowAvatar;
import 'package:whitenoise/widgets/chat_message_bubble.dart';
import 'package:whitenoise/widgets/wn_button.dart';
import 'package:whitenoise/widgets/wn_emoji_picker.dart';
import 'package:whitenoise/widgets/wn_icon.dart';
import 'package:whitenoise/widgets/wn_slate.dart';
import 'package:whitenoise/widgets/wn_system_notice.dart';

class MessageActionsScreen extends HookWidget {
  const MessageActionsScreen({
    super.key,
    required this.message,
    required this.pubkey,
    required this.onAddReaction,
    required this.onRemoveReaction,
    this.onDelete,
    this.onReply,
    this.senderName,
    this.senderPictureUrl,
    this.isGroupChat = false,
    this.getChatMessageQuote,
  });

  final ChatMessage message;
  final String pubkey;
  final Future<void> Function(String emoji) onAddReaction;
  final Future<void> Function(String reactionId) onRemoveReaction;
  final Future<void> Function()? onDelete;
  final void Function(ChatMessage message)? onReply;
  final String? senderName;
  final String? senderPictureUrl;
  final bool isGroupChat;
  final ChatMessageQuoteData? Function(String? replyId)? getChatMessageQuote;

  static Future<void> show(
    BuildContext context, {
    required ChatMessage message,
    required String pubkey,
    required Future<void> Function(String emoji) onAddReaction,
    required Future<void> Function(String reactionId) onRemoveReaction,
    Future<void> Function()? onDelete,
    void Function(ChatMessage message)? onReply,
    String? senderName,
    String? senderPictureUrl,
    bool isGroupChat = false,
    ChatMessageQuoteData? Function(String? replyId)? getChatMessageQuote,
  }) {
    final colors = context.colors;

    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: colors.backgroundPrimary.withValues(alpha: 0.8),
        pageBuilder: (menuContext, _, _) {
          return MessageActionsScreen(
            message: message,
            pubkey: pubkey,
            onAddReaction: onAddReaction,
            onRemoveReaction: onRemoveReaction,
            onDelete: onDelete,
            onReply: onReply,
            senderName: senderName,
            senderPictureUrl: senderPictureUrl,
            isGroupChat: isGroupChat,
            getChatMessageQuote: getChatMessageQuote,
          );
        },
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showEmojiPicker = useState(false);
    final noticeMessage = useState<String?>(null);

    void showNotice(String message) {
      noticeMessage.value = message;
    }

    void dismissNotice() {
      noticeMessage.value = null;
    }

    final isOwnMessage = message.pubkey == pubkey;
    final userReactionIds = Map.fromEntries(
      message.reactions.userReactions
          .where((r) => r.user == pubkey)
          .map((r) => MapEntry(r.emoji, r.reactionId)),
    );
    final selectedEmojis = userReactionIds.keys.toSet();

    Future<void> handleDelete() async {
      try {
        await onDelete?.call();
        if (context.mounted) Navigator.of(context).pop();
      } catch (_) {
        if (context.mounted) {
          showNotice(context.l10n.failedToDeleteMessage);
        }
      }
    }

    Future<void> handleReaction(String emoji) async {
      final reactionId = userReactionIds[emoji];
      try {
        if (reactionId != null) {
          await onRemoveReaction(reactionId);
        } else {
          await onAddReaction(emoji);
        }
        if (context.mounted) Navigator.of(context).pop();
      } catch (_) {
        if (context.mounted) {
          showNotice(
            reactionId != null
                ? context.l10n.failedToRemoveReaction
                : context.l10n.failedToSendReaction,
          );
        }
      }
    }

    return SafeArea(
      child: Column(
        children: [
          if (noticeMessage.value != null)
            WnSystemNotice(
              key: ValueKey(noticeMessage.value),
              title: noticeMessage.value!,
              type: WnSystemNoticeType.error,
              onDismiss: dismissNotice,
            ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 16.h),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final viewportHeight = MediaQuery.sizeOf(context).height;
                  final targetSlateMaxHeight = (viewportHeight - (2 * 96.h)).toDouble();
                  final slateMaxHeight = max(
                    0.0,
                    min(targetSlateMaxHeight, constraints.maxHeight),
                  );
                  debugPrint(
                    '[MessageActions] viewportHeight=$viewportHeight, '
                    'availableHeight=${constraints.maxHeight}, '
                    'slateMaxHeight=$slateMaxHeight, '
                    'showEmojiPicker=${showEmojiPicker.value}',
                  );
                  final modal = ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: slateMaxHeight),
                    child: Builder(
                      builder: (context) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (context.mounted) {
                            final box = context.findRenderObject();
                            if (box is RenderBox && box.hasSize) {
                              debugPrint(
                                '[MessageActions] rendered size: '
                                'width=${box.size.width}, height=${box.size.height}',
                              );
                            }
                          }
                        });
                        return MessageActionsModal(
                          message: message,
                          isOwnMessage: isOwnMessage,
                          currentUserPubkey: pubkey,
                          onDelete: (isOwnMessage && onDelete != null) ? handleDelete : null,
                          onReaction: handleReaction,
                          onEmojiPicker: () => showEmojiPicker.value = !showEmojiPicker.value,
                          selectedEmojis: selectedEmojis,
                          onReply: onReply != null
                              ? () {
                                  Navigator.of(context).pop();
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    onReply!(message);
                                  });
                                }
                              : null,
                          senderName: senderName,
                          senderPictureUrl: senderPictureUrl,
                          isGroupChat: isGroupChat,
                          getChatMessageQuote: getChatMessageQuote,
                          slateMaxHeight: slateMaxHeight,
                        );
                      },
                    ),
                  );
                  return showEmojiPicker.value
                      ? Align(alignment: Alignment.bottomCenter, child: modal)
                      : Center(child: modal);
                },
              ),
            ),
          ),
          if (showEmojiPicker.value)
            WnEmojiPicker(
              onClose: () => showEmojiPicker.value = false,
              onEmojiSelected: handleReaction,
            ),
        ],
      ),
    );
  }
}

class MessageActionsModal extends StatelessWidget {
  const MessageActionsModal({
    super.key,
    required this.message,
    required this.isOwnMessage,
    required this.onReaction,
    required this.onEmojiPicker,
    required this.currentUserPubkey,
    this.onDelete,
    this.selectedEmojis = const {},
    this.onReply,
    this.senderName,
    this.senderPictureUrl,
    this.isGroupChat = false,
    this.getChatMessageQuote,
    this.slateMaxHeight,
  });

  final ChatMessage message;
  final bool isOwnMessage;
  final void Function(String emoji) onReaction;
  final VoidCallback onEmojiPicker;
  final String currentUserPubkey;
  final VoidCallback? onDelete;
  final Set<String> selectedEmojis;
  final VoidCallback? onReply;
  final String? senderName;
  final String? senderPictureUrl;
  final bool isGroupChat;
  final ChatMessageQuoteData? Function(String? replyId)? getChatMessageQuote;
  final double? slateMaxHeight;

  static const List<String> reactions = [
    '❤',
    '😀',
    '👍',
    '👎',
    '🤣',
    '🔥',
    '🦥',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final replyPreview = message.isReply ? getChatMessageQuote?.call(message.replyToId) : null;
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final effectiveSlateMaxHeight =
        slateMaxHeight ?? (viewportHeight - (2 * 96.h)).clamp(320.h, viewportHeight).toDouble();
    final buttonHeight = 48.h;
    final reactionsRowHeight = 40.h;
    final verticalGaps = 16.h + 16.h;
    final copySectionHeight = 8.h + buttonHeight;
    final replySectionHeight = onReply != null ? buttonHeight : 0.0;
    final deleteSectionHeight = onDelete != null ? (8.h + buttonHeight) : 0.0;
    final layoutSafetyBuffer = 56.h;
    final previewOverflowBuffer = 24.h;
    final actionsHeight =
        reactionsRowHeight +
        verticalGaps +
        copySectionHeight +
        replySectionHeight +
        deleteSectionHeight;
    final messageMaxHeightCap = max(
      0.0,
      effectiveSlateMaxHeight - 32.h - actionsHeight - layoutSafetyBuffer - previewOverflowBuffer,
    );
    final bodyLineHeight =
        (context.typographyScaled.medium16Compact.height ?? 18 / 16) *
        (context.typographyScaled.medium16Compact.fontSize ?? 16.sp);
    final estimatedLineCount = max(1, (message.content.length / 30).ceil());
    final estimatedTextHeight = min(
      messageMaxHeightCap,
      (estimatedLineCount * bodyLineHeight) + 32.h + (message.isReply ? 56.h : 0),
    );
    final bubblePadding = 22.h;
    final timestampArea = 12.h;
    final safetyBuffer = 12.h;
    final replyBlockHeight = message.isReply ? 64.h : 0.0;
    final reactionsBlockHeight = message.reactions.byEmoji.isNotEmpty ? 48.h : 0.0;
    final reservedHeight =
        bubblePadding + timestampArea + safetyBuffer + replyBlockHeight + reactionsBlockHeight;
    final minBubbleHeight = reservedHeight + (2 * bodyLineHeight);
    final messagePreviewHeight = max(
      minBubbleHeight,
      min(messageMaxHeightCap, estimatedTextHeight),
    );
    final availableForText = messagePreviewHeight - reservedHeight;
    final maxPreviewLines = max(
      1,
      min(14, (availableForText / bodyLineHeight).floor()),
    );
    debugPrint(
      '[MessageActionsModal] message.content.length=${message.content.length}, '
      'slateMaxHeight=$effectiveSlateMaxHeight, '
      'messagePreviewHeight=$messagePreviewHeight, '
      'messageMaxHeightCap=$messageMaxHeightCap, maxPreviewLines=$maxPreviewLines',
    );

    return WnSlate(
      shrinkWrapContent: true,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final hasBoundedHeight = constraints.hasBoundedHeight;
            return Column(
              mainAxisSize: hasBoundedHeight ? MainAxisSize.max : MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasBoundedHeight)
                  Flexible(
                    fit: FlexFit.loose,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: messagePreviewHeight),
                      child: ClipRect(
                        child: ChatMessageBubble(
                          message: message,
                          isOwnMessage: isOwnMessage,
                          currentUserPubkey: currentUserPubkey,
                          showAvatar: shouldShowAvatar(
                            current: message,
                            next: null,
                            isOwnMessage: isOwnMessage,
                            isGroupChat: isGroupChat,
                          ),
                          senderName: senderName,
                          senderPictureUrl: senderPictureUrl,
                          isGroupChat: isGroupChat,
                          replyPreview: replyPreview,
                          maxTextLines: maxPreviewLines,
                        ),
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: messagePreviewHeight),
                    child: ClipRect(
                      child: ChatMessageBubble(
                        message: message,
                        isOwnMessage: isOwnMessage,
                        currentUserPubkey: currentUserPubkey,
                        showAvatar: shouldShowAvatar(
                          current: message,
                          next: null,
                          isOwnMessage: isOwnMessage,
                          isGroupChat: isGroupChat,
                        ),
                        senderName: senderName,
                        senderPictureUrl: senderPictureUrl,
                        isGroupChat: isGroupChat,
                        replyPreview: replyPreview,
                        maxTextLines: maxPreviewLines,
                      ),
                    ),
                  ),
                SizedBox(height: 8.h),
                Row(
                  children: [
                    ...reactions.map(
                      (emoji) => Expanded(
                        child: _ReactionButton(
                          key: Key('reaction_$emoji'),
                          colors: colors,
                          emoji: emoji,
                          isSelected: selectedEmojis.contains(emoji),
                          onTap: () => onReaction(emoji),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        key: const Key('emoji_picker_button'),
                        onTap: onEmojiPicker,
                        child: Center(
                          child: WnIcon(
                            WnIcons.addEmoji,
                            color: colors.backgroundContentPrimary,
                            size: 20.sp,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16.h),
                if (onReply != null)
                  WnButton(
                    key: const Key('reply_button'),
                    text: context.l10n.reply,
                    type: WnButtonType.outline,
                    size: WnButtonSize.medium,
                    trailingIcon: WnIcons.reply,
                    onPressed: onReply,
                  ),
                Gap(8.h),
                WnButton(
                  key: const Key('copy_button'),
                  text: context.l10n.copyMessage,
                  type: WnButtonType.outline,
                  size: WnButtonSize.medium,
                  trailingIcon: WnIcons.copy,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: message.content));
                    Navigator.of(context).pop();
                  },
                ),
                if (onDelete != null) ...[
                  Gap(8.h),
                  WnButton(
                    key: const Key('delete_button'),
                    text: context.l10n.delete,
                    type: WnButtonType.destructive,
                    size: WnButtonSize.medium,
                    trailingIcon: WnIcons.trashCan,
                    onPressed: onDelete,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({
    super.key,
    required this.colors,
    required this.emoji,
    required this.onTap,
    this.isSelected = false,
  });

  final SemanticColors colors;
  final String emoji;
  final VoidCallback onTap;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Center(
        child: Container(
          padding: EdgeInsets.all(8.w),
          decoration: isSelected
              ? BoxDecoration(
                  color: colors.fillTertiaryActive,
                  borderRadius: BorderRadius.circular(8.r),
                )
              : null,
          child: Text(
            emoji,
            style: context.typographyScaled.medium20,
          ),
        ),
      ),
    );
  }
}
