import 'dart:convert';

import 'package:chat_babakcode/constants/config.dart';
import 'package:chat_babakcode/main.dart';
import 'package:chat_babakcode/models/room.dart';
import 'package:chat_babakcode/providers/auth_provider.dart';
import 'package:chat_babakcode/providers/global_setting_provider.dart';
import 'package:chat_babakcode/ui/pages/chat/chat_page.dart';
import 'package:chat_babakcode/utils/utils.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../models/chat.dart';
import '../utils/hive_manager.dart';

class ChatProvider extends ChangeNotifier {
  io.Socket socket = io.io(
      AppConfig.socketBaseUrl,
      io.OptionBuilder()
          .enableForceNewConnection()
          .disableAutoConnect()
          .setTransports(['websocket']).build());

  /// auth provider proxy
  Auth? auth;

  void initAuth(Auth auth) => this.auth = auth;

  void saveLastViewPortSeenIndex(Room selectedRoom) {
    if (selectedRoom.minViewPortSeenIndex != minIndexOfChatListOnViewPort) {
      // save on database
      _hiveManager.updateMinViewPortSeenIndexOfRoom(
          minIndexOfChatListOnViewPort, selectedRoom);
      // save to local list
      selectedRoom.minViewPortSeenIndex = minIndexOfChatListOnViewPort;
    }

    if ((selectedRoom.lastIndex ?? -1) < maxIndexOfChatListOnViewPort) {
      // save on database
      _hiveManager.updateLastIndexOfRoom(
          maxIndexOfChatListOnViewPort, selectedRoom);
      selectedRoom.lastIndex = maxIndexOfChatListOnViewPort;
    }
  }

  void connectSocket() {
    setConnectionStatus = 'Connecting ...';
    // chatProvider?.clearRoomsList();
    // HiveManager.saveCancel = true;
    getAllRooms();

    socket
      ..auth = {'token': auth?.accessToken}
      ..connect();
  }

  ChatProvider() {
    // socket events
    socket.onConnect((_) {
      setConnectionStatus = 'Connected';
      debugPrint('socket connected');
      socket.emit('getAllMessages', auth?.lastGroupLoadedDate);
    });
    socket.onDisconnect((_) {
      debugPrint('socket disconnected');
      setConnectionStatus = 'Connecting ...';
    });
    socket.onConnectError(_handleSocketErrorsEvent);
    socket.onError(_handleSocketErrorsEvent);
    socket.on('userRooms', _userRoomsEvent);
    socket.on('userRoomChats', _userRoomChatsEvent);
    socket.on('receiveChat', _receiveChatEvent);

    /// check keyboard appeared
    chatFocusNode.addListener(() {
      if (chatFocusNode.hasFocus) {
        if (showSticker || showEmoji || showShareFile) {
          showSticker = false;
          showShareFile = false;
          showEmoji = false;
          notifyListeners();
        }
      }
    });

    /// chat text edit controller listener
    chatController.addListener(() {
      bool showSendChat = chatController.text.isNotEmpty;
      if (showSendChat != this.showSendChat) {
        this.showSendChat = showSendChat;
        notifyListeners();
      }
    });

    itemPositionsListener.itemPositions.addListener(changeScrollIndexListener);
  }

  set setConnectionStatus(String? set) {
    Future.delayed(
      const Duration(seconds: 1),
      () {
        connectionStatus = set;
        notifyListeners();
      },
    );
  }

  String? connectionStatus;

  void changeScrollIndexListener() {
    if (selectedRoom == null) {
      return;
    }

    //
    // if (selectedRoom!.minViewPortSeenIndex != minIndexOfChatListOnViewPort) {
    //   // save on database
    //   _hiveManager.updateMinViewPortSeenIndexOfRoom(
    //       minIndexOfChatListOnViewPort, selectedRoom!);
    //   // save to local list
    //   selectedRoom!.minViewPortSeenIndex = minIndexOfChatListOnViewPort;
    // }
    if ((selectedRoom!.lastIndex ?? -1) < maxIndexOfChatListOnViewPort) {
      // save on database
      // _hiveManager.updateLastIndexOfRoom(
      //     maxIndexOfChatListOnViewPort, selectedRoom!);
      selectedRoom!.lastIndex = maxIndexOfChatListOnViewPort;
      notifyListeners();
    }

    /// load more (next) chats
    ///
    /// change reachedToEnd to true when the chat list empty after request
    if (selectedRoom!.chatList.isNotEmpty &&
        (selectedRoom!.chatList.indexOf(selectedRoom!.chatList.last) -
                    maxIndexOfChatListOnViewPort)
                .abs() <=
            3 &&
        !selectedRoom!.reachedToEnd &&
        !loadingLoadMoreNext &&
        selectedRoom!.lastChat!.chatNumberId !=
            selectedRoom!.chatList.last.chatNumberId) {
      _loadMoreNext();
    } else if (minIndexOfChatListOnViewPort <= 3 &&
        selectedRoom!.reachedToStart == false &&
        /// load more (previous) chats
        ///
        /// change reachedToStart to true when the chat list empty after request
        selectedRoom!.chatList.isNotEmpty &&
        minIndexOfChatListOnViewPort == 0 &&
        !selectedRoom!.reachedToStart &&
        !loadingLoadMorePrevious) {
      _loadMorePrevious();
    }
  }

  void disconnectSocket() {
    socket.disconnect();
  }

  TextEditingController chatController = TextEditingController();

  bool showSendChat = false;

  FocusNode chatFocusNode = FocusNode();

  bool showShareFile = false;
  bool showEmoji = false;
  bool showSticker = false;
  bool loadingLoadMoreNext = false;
  bool loadingLoadMorePrevious = false;

  List<Room> rooms = [];
  final _hiveManager = HiveManager();

  ItemScrollController itemScrollController = ItemScrollController();
  ItemPositionsListener itemPositionsListener = ItemPositionsListener.create();

  int get maxIndexOfChatListOnViewPort =>
      itemPositionsListener.itemPositions.value
          .where((ItemPosition position) => position.itemLeadingEdge < 1)
          .reduce((ItemPosition max, ItemPosition position) =>
      position.itemLeadingEdge > max.itemLeadingEdge ? position : max)
          .index;

  int get minIndexOfChatListOnViewPort =>
      itemPositionsListener.itemPositions.value
          .where((ItemPosition position) => position.itemTrailingEdge > 0)
          .reduce((ItemPosition min, ItemPosition position) =>
      position.itemTrailingEdge < min.itemTrailingEdge ? position : min)
          .index;

  Room? selectedRoom;








  void emojiToggle() {
    showEmoji = !showEmoji;
    if (showEmoji) {
      if (chatFocusNode.hasFocus) {
        FocusManager.instance.primaryFocus?.unfocus();
      }

      if (showSticker || showShareFile) {
        showSticker = false;
        showShareFile = false;
      }
    }
    notifyListeners();
  }

  void shareFileToggle() {
    showShareFile = !showShareFile;
    if (showShareFile) {
      if (chatFocusNode.hasFocus) {
        FocusManager.instance.primaryFocus?.unfocus();
      }

      if (showSticker || showEmoji) {
        showSticker = false;
        showEmoji = false;
      }
    }
    notifyListeners();
  }

  void stickerToggle() {
    showSticker = !showSticker;
    if(showSticker){

      if (chatFocusNode.hasFocus) {
        FocusManager.instance.primaryFocus?.unfocus();
      }

      if (showEmoji || showShareFile) {
        showEmoji = false;
        showShareFile = false;
      }
    }
    notifyListeners();
  }


  void searchRoomWith(
      {required String roomType,
        required String searchType,
        required String searchText,
        required BuildContext context,
        Function? callBack}) {
    /// search from exist rooms
    /// then if not find room,
    /// search from server

    bool foundLocalExistGroup = false;
    rooms
        .where((element) => element.roomType == RoomType.pvUser)
        .toList()
        .forEach((room) {
      if (room.members
          .where((element) =>
      ((searchType == 'token')
          ? element.user!.publicToken
          : element.user?.username) ==
          searchText)
          .isNotEmpty) {
        /// room found
        selectedRoom = room;
        Navigator.pop(context);
        if (GlobalSettingProvider.isPhonePortraitSize) {
          Navigator.push(
              navigatorKey.currentContext!,
              CupertinoPageRoute(
                builder: (context) => const ChatPage(),
              ));
        } else {
          notifyListeners();
        }
        foundLocalExistGroup = true;
        callBack?.call({
          'success': true,
          'findFromExistRoom': true,
        });
      }
    });
    if (foundLocalExistGroup) {
      return;
    }

    socket.emitWithAck('searchRoom', {
      'searchType': searchType,
      'roomType': roomType,
      'searchText': searchText,
    }, ack: (data) {
      if (kDebugMode) {
        print(data);
      }

      if (data['success']) {
        callBack?.call({
          'success': true,
          'findFromExistRoom': false,
        });
        Navigator.pop(context);
        selectedRoom = Room.fromJson(data['room'], false);

        if (GlobalSettingProvider.isPhonePortraitSize) {
          Navigator.push(
            navigatorKey.currentContext!,
            CupertinoPageRoute(
              builder: (context) => const ChatPage(),
            ),
          );
        } else {
          notifyListeners();
        }
      } else {
        callBack?.call(
            {'success': false, 'findFromExistRoom': false, 'msg': data['msg']});
      }
    });
  }





  void emitText(Room room) {
    if (chatController.text.isEmpty) {
      return;
    }
    Map data = {
      'roomId': room.id ?? 'new',
      'chat': chatController.text,
      'type': 'text'
    };

    if (room.id == null &&
        room.roomType == RoomType.pvUser &&
        room.newRoomToGenerate) {
      data['userId'] = room.members
          .firstWhere((element) => element.user!.id != auth!.myUser!.id!)
          .user!
          .id;
    }
    socket.emitWithAck('sendChat', data, ack: (data) {
      if (kDebugMode) {
        print('sendChat ack res: $data');
      }
      if (data['success']) {
        chatController.clear();
        // _receiveChatEvent(data['data']);
        notifyListeners();
      } else {
        Utils.showSnack(navigatorKey.currentContext!, data['msg']);
      }
    });
  }

  Future emitFile(Uint8List file, String type)async{
    socket.emitWithAck('sendFile', {
      'file': file,
      'type': type
    }, ack: (data){
      print(data);
    });
  }


  void recordStart() {}

  void recordStop(BuildContext context, Room room) {}

  void onEmojiSelected(Emoji emoji) {
    chatController
      ..text += emoji.emoji
      ..selection = TextSelection.fromPosition(
          TextPosition(offset: chatController.text.length));
  }

  void onBackspacePressed() {
    chatController
      ..text = chatController.text.characters.skipLast(1).toString()
      ..selection = TextSelection.fromPosition(
          TextPosition(offset: chatController.text.length));
  }

  void changeSelectedRoom(Room room) async {
    if(selectedRoom == room){
      return;
    }

    if (GlobalSettingProvider.isPhonePortraitSize) {
      selectedRoom = room;
      notifyListeners();
      return;
    }
    if (selectedRoom != null) {
      deselectRoom();
    }

    await Future.delayed(
        const Duration(milliseconds: 100), () => selectedRoom = room);
    notifyListeners();
  }

  void deselectRoom() {
    selectedRoom = null;
    notifyListeners();
  }

  void _userRoomChatsEvent(data) {
    if (kDebugMode) {
      print('userRoomChats => $data');
    }

    try {
      if (data['success']) {
        final roomId = data['roomId'];
        final indexOfRoom = rooms.indexWhere((element) => element.id == roomId);
        if (indexOfRoom == -1) {
          /// todo : check exist list before add data
        }
        rooms[indexOfRoom]
            .chatList
            .addAll(Chat.getChatsFromJsonList(data['chats']));

        setConnectionStatus = null;
        notifyListeners();

        /// save chats
        _hiveManager.saveChats(
            rooms[indexOfRoom].chatList, rooms[indexOfRoom].id!);
      }
    } catch (e) {
      if (kDebugMode) {
        print('userRoomChats exception: $e');
      }
    }
  }

  void _userRoomsEvent(data) {
    if (kDebugMode) {
      print('userRooms => $data');
    }
    try {
      if (data['success']) {
        final _rooms = data['rooms'] as List;
        setConnectionStatus = _rooms.isNotEmpty ? 'Updating ...' : null;
        for (Map room in _rooms) {
          if (rooms.where((element) => element.id == room['_id']).isEmpty) {
            rooms.add(Room.fromJson(room, false));
          }
        }

        rooms.sort((a, b) => b.changeAt!.compareTo(b.changeAt!));
        notifyListeners();
        if (rooms.isNotEmpty) {
          auth!.setLastGroupLoadedDate(rooms[0].changeAt.toString());
        }
        _hiveManager.saveRooms(rooms);
      }
    } catch (e) {
      if (kDebugMode) {
        print('userRooms exception $e');
      }
    }
  }

  void _receiveChatEvent(data) async {
    if (kDebugMode) {
      print('receiveChat => $data');
    }
    try {
      Chat chat = Chat.fromJson(data['chat']);

      int indexOfRoom = rooms.indexWhere((element) => element.id == chat.room);

      /// add the room to the local list if not exist
      if (indexOfRoom == -1) {
        /// request to get room details
        /// or insert from chat `room` property
        Room room = Room.fromJson(data['room'], false);

        rooms.add(room);

        /// after get room, update ``indexOfRoom``
        indexOfRoom = rooms.indexOf(room);
      }

      /// get targetRoom from local list
      Room targetRoom = rooms[indexOfRoom];
      if (targetRoom.id == selectedRoom?.id) {
        selectedRoom = targetRoom;
      }

      /// check last chat of the target room
      if (targetRoom.lastChat == null) {
        targetRoom.lastChat = chat;

        targetRoom.chatList.add(chat);
      }
      else {
        /// if received new (chat number id) - 1 is room lastChat of
        /// `loaded` chat list number id
        /// then we reached to end of the chat list
        /// that means we won't load more of list
        if (chat.chatNumberId! - 1 ==
                targetRoom
                    .chatList[targetRoom.chatList.length - 1].chatNumberId ||
            targetRoom.reachedToEnd) {
          targetRoom.chatList.add(chat);
        } else if (chat.user!.id == auth!.myUser!.id &&
            !targetRoom.reachedToEnd) {
          /// get the last 50 chats of the room if
          /// the sender user is from our account
          /// and we not reached to the end of target list
          targetRoom.chatList.clear();
          notifyListeners();

          socket.emitWithAck('loadMorePrevious',
              jsonEncode({'before': chat.chatNumberId, 'room': targetRoom.id}),
              ack: (data) {
            data = jsonDecode(data);
            if (data['success']) {
              final chatList = data['chats'] as List;
              targetRoom.chatList =
                  chatList.map((e) => Chat.fromJson(e)).toList();
              targetRoom.chatList.add(chat);
              targetRoom.chatList
                  .sort((a, b) => a.chatNumberId!.compareTo(b.chatNumberId!));

              /// after add chat to chat list of the target room then
              /// save chat
              _hiveManager.saveChats(targetRoom.chatList, targetRoom.id!,
                  clearSavedList: true);
            } else {
              Utils.showSnack(navigatorKey.currentContext!, data['msg']);
            }
          });
        }
      }

      /// after add chat to chat list of the target room then
      /// save chat
      _hiveManager.saveChats([chat], targetRoom.id!);

      /// else just update the last chat of list
      targetRoom.lastChat = chat;
      targetRoom.changeAt = chat.utcDate;
      _hiveManager.updateRoom(targetRoom);
      auth!.setLastGroupLoadedDate(targetRoom.changeAt.toString());

      rooms.sort((a, b) => b.changeAt!.compareTo(a.changeAt!));

      /// if we are at end of the list then scroll to received new chat
      if ((selectedRoom == targetRoom &&
              (maxIndexOfChatListOnViewPort - targetRoom.chatList.length)
                      .abs() <=
                  5) ||
          (selectedRoom == targetRoom && chat.user!.id == auth!.myUser!.id)) {
        itemScrollController.scrollTo(
            index: targetRoom.chatList.length - 1,
            duration: const Duration(milliseconds: 1000),
            alignment: .3);
      }
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print(e);
      }
    }
  }

  void _handleSocketErrorsEvent(error) async {
    try {
      debugPrint('socket Error $error');
      if (error['message'] == 'auth_error') {
        socket.disconnect();
        await auth?.logOut();
      }
    } catch (e) {
      if (kDebugMode) {
        print(e);
      }
    }
  }

  void getAllRooms() async {
    rooms = await _hiveManager.getAllRooms();
    rooms.sort((a, b) => b.changeAt!.compareTo(a.changeAt!));
    notifyListeners();
    for (var room in rooms) {
      await getRoomChatsFromDatabase(room);
    }
    notifyListeners();
  }

  void clearRoomsList() async {
    await _hiveManager.clearRooms();
  }

  Future<void> getRoomChatsFromDatabase(Room room) async {
    await _hiveManager
        .getAllChatsOf(room)
        .then((value) => {room.chatList = value, notifyListeners()});
  }

  Future<void> _loadMoreNext() async {
    loadingLoadMoreNext = true;
    notifyListeners();

    socket.emitWithAck(
        'loadMoreNext',
        jsonEncode(
            {'room': selectedRoom?.id, 'after': selectedRoom?.lastIndex}),
        ack: (res) {
      res = jsonDecode(res);
      loadingLoadMoreNext = false;
      if (res['success']) {
        List<Chat> _receivedChats = [];
        for (var item in res['chats']) {
          _receivedChats.add(Chat.fromJson(item));
        }
        if (_receivedChats.isEmpty) {
          selectedRoom!.reachedToEnd = true;
        }
        selectedRoom!.chatList.addAll(_receivedChats);
        _hiveManager.saveChats(_receivedChats, selectedRoom!.id!);
      }
      // notifyListeners();
      notifyListeners();
      if (kDebugMode) {
        print(res);
      }
    });
    // selectedRoom.chatList
    // .
  }

  void _loadMorePrevious() {
    loadingLoadMorePrevious = true;
    notifyListeners();

    socket.emitWithAck(
        'loadMorePrevious',
        jsonEncode({
          'room': selectedRoom?.id,
          'before': selectedRoom?.chatList.first.chatNumberId
        }), ack: (res) {
      res = jsonDecode(res);
          loadingLoadMorePrevious = false;
      if (res['success']) {
        List<Chat> _receivedChats = [];
        for (var item in res['chats']) {
          _receivedChats.add(Chat.fromJson(item));
        }
        if (_receivedChats.isEmpty) {
          selectedRoom!.reachedToStart = true;
        }
        selectedRoom!.chatList.addAll(_receivedChats);
        selectedRoom!.chatList.sort((a, b) => a.chatNumberId!.compareTo(b.chatNumberId!));
        _hiveManager.saveChats(_receivedChats, selectedRoom!.id!);
      }
      notifyListeners();
    });
  }

  Future<void> clearDatabase() async => await _hiveManager.clear();

  Future sendFile(Uint8List bytes) async {
    Chat chat = Chat()..fileUrl = bytes.toString()..type = ChatType.photo..user = auth?.myUser;
    selectedRoom?.chatList.add(chat);
    notifyListeners();
  }
}
