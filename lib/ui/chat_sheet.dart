import 'package:flutter/material.dart';

import '../room_controller.dart';
import '../theme.dart';

void showChat(BuildContext context, RoomController room) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: ConnectColors.deep,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final inset = MediaQuery.viewInsetsOf(context).bottom;
      return Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: ChatSheet(room: room),
      );
    },
  );
}

class ChatSheet extends StatefulWidget {
  const ChatSheet({super.key, required this.room});

  final RoomController room;

  @override
  State<ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<ChatSheet> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    if (widget.room.sendChat(_text.text)) _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final height = MediaQuery.sizeOf(context).height * 0.52;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Chat',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListenableBuilder(
                  listenable: room,
                  builder: (context, _) {
                    final lines = room.chat;
                    if (lines.isEmpty) {
                      return const Align(
                        alignment: Alignment.topLeft,
                        child: Text(
                          'Type a message. Friends in this room will see it.',
                          style: TextStyle(color: ConnectColors.muted),
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: lines.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final line = lines[index];
                        final mine = line.id == room.selfId;
                        return Align(
                          alignment: mine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.sizeOf(context).width * 0.78,
                            ),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: mine
                                    ? const Color(0xFF123844)
                                    : ConnectColors.tile,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: mine
                                      ? ConnectColors.cyan.withValues(
                                          alpha: 0.7,
                                        )
                                      : ConnectColors.line,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      line.name,
                                      style: TextStyle(
                                        color: mine
                                            ? ConnectColors.cyan
                                            : ConnectColors.muted,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      line.text,
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('chat-field'),
                      controller: _text,
                      textCapitalization: TextCapitalization.sentences,
                      cursorColor: ConnectColors.cyan,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'Message',
                        filled: true,
                        fillColor: ConnectColors.tile,
                        isDense: true,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    key: const Key('chat-send'),
                    onPressed: _send,
                    style: TextButton.styleFrom(
                      foregroundColor: ConnectColors.cyan,
                    ),
                    child: const Text('Send'),
                  ),
                ],
              ),
              ListenableBuilder(
                listenable: room,
                builder: (context, _) {
                  final note = room.updateNote;
                  final offer = room.updateOffer;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (note != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            note,
                            style: const TextStyle(
                              color: ConnectColors.muted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          key: const Key('check-update'),
                          onPressed: room.updateBusy
                              ? null
                              : () {
                                  if (offer != null) {
                                    room.installUpdate();
                                  } else {
                                    room.lookForUpdate(manual: true);
                                  }
                                },
                          style: TextButton.styleFrom(
                            foregroundColor: ConnectColors.cyan,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            offer == null
                                ? 'Check for an update'
                                : 'Install ${offer.version}',
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
