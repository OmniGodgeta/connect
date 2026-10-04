import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'alerts.dart';
import 'audio_io.dart';
import 'name_store.dart';
import 'relay.dart';
import 'room_controller.dart';
import 'room_store.dart';
import 'talk_settings.dart';
import 'theme.dart';
import 'ui/name_page.dart';
import 'ui/room_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: ConnectColors.ink,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  final prefs = await SharedPreferences.getInstance();
  final controller = RoomController(
    relay: SocketRelay(),
    audio: DeviceAudio(),
    names: PrefsNameStore(prefs),
    settings: PrefsTalkSettings(prefs),
    rooms: PrefsRoomStore(prefs),
    alerts: PlatformAlerts(),
  );
  runApp(ConnectApp(controller: controller));
}

class ConnectApp extends StatefulWidget {
  const ConnectApp({super.key, required this.controller});

  final RoomController controller;

  @override
  State<ConnectApp> createState() => _ConnectAppState();
}

class _ConnectAppState extends State<ConnectApp> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
    widget.controller.boot();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.controller;
    final Widget home = switch (room.phase) {
      RoomPhase.needName => NamePage(
        onSubmit: room.setName,
        error: room.banner,
      ),
      RoomPhase.left => LeftPage(
        onJoin: () {
          room.join();
        },
      ),
      _ => room.picking ? RoomsPage(room: room) : RoomPage(room: room),
    };
    return MaterialApp(
      title: 'Connect',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: connectTheme(),
      darkTheme: connectTheme(),
      home: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) room.background();
        },
        child: Scaffold(backgroundColor: Colors.transparent, body: home),
      ),
    );
  }
}
