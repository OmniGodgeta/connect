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

class _ConnectAppState extends State<ConnectApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onChange);
    widget.controller.boot();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      widget.controller.enterBackground();
    } else if (state == AppLifecycleState.resumed) {
      widget.controller.leaveBackground();
    }
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
      navigatorKey: _navigatorKey,
      title: 'Connect',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: connectTheme(),
      darkTheme: connectTheme(),
      home: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          final nav = _navigatorKey.currentState;
          if (nav != null && nav.canPop()) {
            nav.pop();
            return;
          }
          room.background();
        },
        child: Scaffold(backgroundColor: Colors.transparent, body: home),
      ),
    );
  }
}
