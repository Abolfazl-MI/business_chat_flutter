import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../models/chat.dart';
import '../../../models/room.dart';
import '../../../providers/chat_provider.dart';
import '../../../providers/global_setting_provider.dart';
import 'chat_text_item.dart';

class ChatScrollableList extends StatefulWidget {
  const ChatScrollableList({Key? key}) : super(key: key);

  @override
  State<ChatScrollableList> createState() => _ChatScrollableListState();
}

class _ChatScrollableListState extends State<ChatScrollableList> {

  int? minInitIndex;

  @override
  void initState() {
    super.initState();
    final chatProvider = context.read<ChatProvider>();
    minInitIndex = chatProvider.selectedRoom?.minViewPortSeenIndex;
  }

  @override
  Widget build(BuildContext context) {

    final chatProvider = context.watch<ChatProvider>();

    return ScrollablePositionedList.builder(
      padding: const EdgeInsets.only(top: 100),
      shrinkWrap: true,
      scrollDirection: Axis.vertical,
      itemScrollController: chatProvider.itemScrollController,
      addAutomaticKeepAlives: true,
      initialScrollIndex: minInitIndex ?? 0,
      itemPositionsListener: chatProvider.itemPositionsListener,
      itemCount: chatProvider.selectedRoom!.chatList.length,
      itemBuilder: chatItem,
    );
  }


  Widget chatItem(BuildContext context, int index) {
    double _width = MediaQuery.of(context).size.width;

    var chatProvider = context.read<ChatProvider>();

    Room room = chatProvider.selectedRoom!;

    Chat? chat = room.chatList.get(index);

    bool fromMyAccount = chat.user!.id == chatProvider.auth!.myUser!.id;
    bool previousChatFromUser = false;
    bool nextChatFromUser = false;
    bool middleChatFromUser = false;

    try {
      previousChatFromUser = (room.chatList.get(index - 1).user!.id ==
          chatProvider.auth!.myUser!.id) ==
          fromMyAccount;
      nextChatFromUser = (room.chatList.get(index - 1).user!.id ==
          chatProvider.auth!.myUser!.id) ==
          fromMyAccount;
      middleChatFromUser = (previousChatFromUser && nextChatFromUser);
      // ignore: empty_catches
    } catch (e) {}
    // if (kDebugMode) {
    //   print('--- ( $index ) -------------------------');
    //   print('fromMyAccount = $fromMyAccount');
    //   print('previusChatFromUser = $previusChatFromUser');
    //   print('nextChatFromUser = $nextChatFromUser');
    //   print('middleChatFromUser = $middleChatFromUser');
    // }

    return Container(
      padding: EdgeInsets.only(
          right: 8,
          left: 8,
          bottom: middleChatFromUser
              ? 2
              : nextChatFromUser
              ? 2
              : previousChatFromUser
              ? 2
              : 16,
          top: middleChatFromUser
              ? 2
              : previousChatFromUser
              ? 2
              : nextChatFromUser
              ? 2
              : 16),
      alignment: fromMyAccount ? Alignment.bottomRight : Alignment.bottomLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!fromMyAccount)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                height: 36,
                width: 36,
                child: nextChatFromUser
                    ? null
                    : Card(
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  clipBehavior: Clip.antiAliasWithSaveLayer,
                  child: Image.asset(
                    'assets/images/p2.jpg',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          Container(
            constraints: BoxConstraints(
              maxWidth: _width *
                  (GlobalSettingProvider.isPhonePortraitSize ? .8 : .3),
            ),

            ///
            child: ChatTextItem(index, fromMyAccount, previousChatFromUser,
                nextChatFromUser, middleChatFromUser),
          ),
        ],
      ),
    );
  }
}
