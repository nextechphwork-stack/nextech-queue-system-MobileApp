import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'firebase_options.dart';
import '../theme/app_theme.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// ── App Constants (matches firebase-config.js) ───────────────────────────────
const String kUniName = "";
const String kAppTitle = 'Quelio';
const List<Map<String, String>> kDepts = [
  {'key': 'registrar', 'label': ' Registrar', 'short': 'Registrar'},
  {'key': 'accounting', 'label': ' Accounting', 'short': 'Accounting'},
  {
    'key': 'scholarship',
    'label': ' Scholarship & Grants',
    'short': 'Scholarship'
  },
];

// ── Colours (mirrors CSS vars) ────────────────────────────────────────────────
// Primary
const Color kNavy = Color(0xFF3B82F6);
const Color kNavy2 = Color(0xFF5B9BFF);
const Color kNavy3 = Color(0xFF7CB8FF);

// Accent
const Color kGold = Color(0xFFFFC857);
const Color kGold2 = Color(0xFFFFD875);

// Background
const Color kCream = Color(0xFFF6F9FF);
const Color kIvory = Color(0xFFFFFFFF);
const Color kIvory2 = Color(0xFFE7EEF9);

// Text
const Color kText3 = Color(0xFF7B8BA5);

// Status
const Color kGreen = Color(0xFF33C06D);
const Color kAmber = Color(0xFFFFB648);
const Color kRed = Color(0xFFFF5A5F);

// Department
const Color kBlue = Color(0xFF4F8EF7);

// Handles push notifications that arrive while the app is fully closed or
// backgrounded. Must be a top-level (or static) function — the OS runs it in
// its own isolate, so Firebase has to be re-initialized here. This only
// needs to exist for the OS to be able to deliver the notification; the
// actual "you're almost up" / "served" push is triggered server-side (see
// functions/index.js) once that Cloud Function is deployed.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel _pushChannel = AndroidNotificationChannel(
  'quelio_default_channel',
  'Quelio Notifications',
  description: 'Ticket status updates',
  importance: Importance.high,
);
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const QueuePlusApp());
}

class QueuePlusApp extends StatelessWidget {
  const QueuePlusApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppTitle,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: kNavy),
        textTheme: GoogleFonts.outfitTextTheme(),
        useMaterial3: true,
      ),
      home: const _SplashScreen(),
    );
  }
}

// ── Splash / Loading Screen ─────────────────────────────────────────────────
class _SplashScreen extends StatefulWidget {
  const _SplashScreen();
  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 400),
          pageBuilder: (_, __, ___) => const MobileTrackerPage(),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/logo_loading.png',
              width: 180,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 36),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(kNavy),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Data model ────────────────────────────────────────────────────────────────
class QueueItem {
  final String key;
  final String ticketId;
  final int number;
  final String department;
  final String deptLabel;
  final String status;
  final String issuedAt;

  const QueueItem({
    required this.key,
    required this.ticketId,
    required this.number,
    required this.department,
    required this.deptLabel,
    required this.status,
    required this.issuedAt,
  });

  factory QueueItem.fromEntry(String k, Map<dynamic, dynamic> v) {
    return QueueItem(
      key: k,
      ticketId: (v['ticketId'] ?? '').toString(),
      number: int.tryParse(v['number']?.toString() ?? '0') ?? 0,
      department: (v['department'] ?? '').toString(),
      deptLabel: (v['deptLabel'] ?? v['department'] ?? '').toString(),
      status: (v['status'] ?? 'waiting').toString(),
      issuedAt: (v['issuedAt'] ?? '').toString(),
    );
  }

  String get pad3 => number > 0 ? number.toString().padLeft(3, '0') : '—';
}

// ── Main page ─────────────────────────────────────────────────────────────────
class MobileTrackerPage extends StatefulWidget {
  const MobileTrackerPage({super.key});
  @override
  State<MobileTrackerPage> createState() => _MobileTrackerPageState();
}

class _MobileTrackerPageState extends State<MobileTrackerPage> {
  // Firebase
  final _db = FirebaseDatabase.instance.ref('queue');
  final _messaging = FirebaseMessaging.instance;
  StreamSubscription<DatabaseEvent>? _sub;

  // State
  List<QueueItem> _queue = [];
  String _myTicket = '';
  String? _notifiedAt10;
  bool _connected = false;
  bool _servedHandled = false;

  // Valid ticket formats: R001-R009, R010-R099, R100 (and same for A / S).
  static final RegExp _ticketFormat = RegExp(r'^([RAS])(\d{3})$');

  // Controllers
  final _ticketCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  // Toast queue
  final List<OverlayEntry> _toasts = [];

  @override
  void initState() {
    super.initState();
    _loadMyTicket();
    _listenFirebase();
    _initPush();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticketCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Firebase ────────────────────────────────────────────────────────────────
  void _listenFirebase() {
    _sub = _db.onValue.listen((event) {
      final raw = event.snapshot.value;
      List<QueueItem> items = [];
      if (raw is Map) {
        raw.forEach((k, v) {
          if (v is Map) items.add(QueueItem.fromEntry(k.toString(), v));
        });
      }
      setState(() {
        _queue = items;
        _connected = true;
      });
      _checkNotifications();
      _checkServed();
    }, onError: (_) {
      setState(() => _connected = false);
    });
  }

  // ── Persistence ─────────────────────────────────────────────────────────────
  Future<void> _loadMyTicket() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('my_ticket') ?? '';
    setState(() => _myTicket = saved);
    if (saved.isNotEmpty) _registerPushToken(saved);
  }

  Future<void> _saveMyTicket(String val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('my_ticket', val);
  }

  Future<void> _clearMyTicketPref() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('my_ticket');
  }

  // ── Ticket validation ────────────────────────────────────────────────────────
  String? _deptFromTicket(String val) {
    if (val.isEmpty) return null;
    switch (val[0]) {
      case 'R':
        return 'registrar';
      case 'A':
        return 'accounting';
      case 'S':
        return 'scholarship';
      default:
        return null;
    }
  }

  bool _isValidTicketFormat(String val) {
    final m = _ticketFormat.firstMatch(val);
    if (m == null) return false;
    final n = int.tryParse(m.group(2)!);
    if (n == null || n < 1 || n > 100) return false;
    return true;
  }

  // ── Ticket actions ───────────────────────────────────────────────────────────
  Future<void> _handleTrackPressed() async {
    final val = _ticketCtrl.text.trim().toUpperCase();

    if (val.isEmpty || !_isValidTicketFormat(val)) {
      await _showInvalidInputDialog();
      return;
    }

    // Already-served check — alert immediately, don't ask for confirmation.
    final existing = _queue.firstWhereOrNull((q) => q.ticketId == val);
    if (existing != null && existing.status == 'done') {
      _toast('Ticket has been served.', isOk: true);
      return;
    }

    final confirmed = await _showConfirmDialog(val);
    if (confirmed == true) {
      _startTracking(val);
    }
    // If "No" or dismissed, leave the field as-is so they can correct it.
  }

  void _startTracking(String val) {
    setState(() {
      _myTicket = val;
      _notifiedAt10 = null;
      _servedHandled = false;
    });
    _saveMyTicket(val);
    _ticketCtrl.clear();
    _registerPushToken(val);
    _toast('Tracking ticket $val', isOk: true);
  }

  void _clearMyTicket() {
    final oldTicket = _myTicket;
    setState(() {
      _myTicket = '';
      _notifiedAt10 = null;
      _servedHandled = false;
    });
    _clearMyTicketPref();
    _unregisterPushToken(oldTicket);
  }

  Future<void> _showInvalidInputDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invalid Input'),
        content: const Text(
            'Please put a valid ticket number.\n\nAccepted formats: R001–R100, A001–A100, or S001–S100.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showConfirmDialog(String val) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Ticket Number'),
        content: Text('Is "$val" the ticket number printed on your ticket?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
  }

  // ── Notifications (in-app only — no permission plugin needed) ───────────────
  void _checkNotifications() {
    if (_myTicket.isEmpty) return;
    final myItem = _findMyItem();
    if (myItem == null) return;
    final waiting = _queue.where((q) => q.status == 'waiting').toList();
    final ahead = waiting
        .where((q) =>
            q.number < myItem.number && q.department == myItem.department)
        .length;

    final notifyKey = '${_myTicket}:10:${myItem.number}';
    if (myItem.status == 'waiting' &&
        ahead <= 10 &&
        _notifiedAt10 != notifyKey) {
      _notifiedAt10 = notifyKey;
      _toast(' You are $ahead position${ahead == 1 ? '' : 's'} away!',
          isOk: true);
    }
  }

  // If the ticket currently being tracked has been served, alert the user
  // and remove the tracked ticket (input + "Track" button reappear, and the
  // "Your Ticket" label is cleared).
  void _checkServed() {
    if (_myTicket.isEmpty || _servedHandled) return;
    final myItem = _findMyItem();
    if (myItem != null && myItem.status == 'done') {
      _servedHandled = true;
      _toast('🎉 Ticket has been served.', isOk: true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _clearMyTicket();
      });
    }
  }

  // ── Push notifications (works even when the app is closed) ──────────────────
  // NOTE: Getting the *permission* + *token* wired up client-side (below) is
  // only half of what makes "notify me even if the app is closed" work. The
  // other half is a server-side trigger that watches Firebase and actually
  // sends the push — see functions/index.js. That Cloud Function needs to be
  // deployed separately (`firebase deploy --only functions`, requires the
  // Blaze plan) since it can't be shipped inside the Flutter app itself.
  Future<void> _initPush() async {
    try {
      await _messaging.requestPermission(alert: true, badge: true, sound: true);

      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      await _localNotifications.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_pushChannel);

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final notification = message.notification;
        if (notification != null) {
          _localNotifications.show(
            notification.hashCode,
            notification.title,
            notification.body,
            NotificationDetails(
              android: AndroidNotificationDetails(
                _pushChannel.id,
                _pushChannel.name,
                channelDescription: _pushChannel.description,
                importance: Importance.high,
                priority: Priority.high,
              ),
              iOS: const DarwinNotificationDetails(),
            ),
          );
        }
      });
    } catch (_) {
      // Permission dialog/plugin not available on this platform — safe to ignore.
    }
  }

  Future<void> _registerPushToken(String ticket) async {
    try {
      final token = await _messaging.getToken();
      if (token == null) return;
      final dept = _deptFromTicket(ticket);
      await FirebaseDatabase.instance.ref('queue_tokens/$ticket').set({
        'token': token,
        'department': dept,
        'updatedAt': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      // No network / messaging unavailable — in-app alerts still work.
    }
  }

  Future<void> _unregisterPushToken(String ticket) async {
    if (ticket.isEmpty) return;
    try {
      await FirebaseDatabase.instance.ref('queue_tokens/$ticket').remove();
    } catch (_) {}
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────
  QueueItem? _findMyItem() {
    if (_myTicket.isEmpty) return null;
    try {
      return _queue.firstWhere((q) =>
          q.ticketId == _myTicket ||
          q.number.toString().padLeft(3, '0') == _myTicket);
    } catch (_) {
      return null;
    }
  }

  Color _deptColor(String dept) {
    switch (dept) {
      case 'registrar':
        return kNavy2;
      case 'accounting':
        return kNavy2;
      case 'scholarship':
        return kNavy2;
      default:
        return kNavy;
    }
  }

  String _deptEmoji(String dept) {
    switch (dept) {
      case 'registrar':
        return '';
      case 'accounting':
        return '';
      case 'scholarship':
        return '';
      default:
        return '';
    }
  }

  void _toast(String msg, {bool isOk = false, bool isError = false}) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
        builder: (_) => _ToastWidget(
              msg: msg,
              isOk: isOk,
              isError: isError,
              onDone: () {
                entry.remove();
                _toasts.remove(entry);
              },
            ));
    overlay.insert(entry);
    _toasts.add(entry);
  }

  // ── QR Scanner ───────────────────────────────────────────────────────────────
  void _openQrScanner() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QrScannerSheet(
        onScanned: (ticketId) {
          final val = ticketId.trim().toUpperCase();
          if (!_isValidTicketFormat(val)) {
            _toast('Invalid Input — please put a valid ticket number.',
                isError: true);
            return;
          }
          final existing = _queue.firstWhereOrNull((q) => q.ticketId == val);
          if (existing != null && existing.status == 'done') {
            _toast('Ticket has been served.', isOk: true);
            return;
          }
          _startTracking(val);
        },
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FF),
      body: SafeArea(
        child: Column(children: [
          _buildHeader(),
          Expanded(
            child: Container(
              color: kCream,
              child: SingleChildScrollView(
                controller: _scrollCtrl,
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildMyTicketCard(),
                      const SizedBox(height: 12),
                      _buildTrackSection(),
                      const SizedBox(height: 12),
                      _buildStatusBanners(),
                      _buildDeptServingGrid(),
                      const SizedBox(height: 12),
                      _buildQueueSection(),
                      const SizedBox(height: 12),
                      _buildFooter(),
                      const SizedBox(height: 12),
                    ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/images/logo_header.png',
            width: 56,
            height: 56,
            fit: BoxFit.contain,
          ),
          const Spacer(),
          _ConnectionDot(connected: _connected),
        ],
      ),
    );
  }

  // ── My Ticket Card ───────────────────────────────────────────────────────────
  Widget _buildMyTicketCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF4F8EF7),
            Color(0xFF6BA8FF),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      child: Stack(children: [
        // Decorative circle
        Positioned(
          top: -30,
          right: -30,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xffffffff).withOpacity(0.07),
            ),
          ),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Text('YOUR TICKET',
              style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 3,
                  color: Colors.white.withOpacity(0.8),
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (_myTicket.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Enter your ticket below',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 13,
                      fontStyle: FontStyle.italic)),
            )
          else ...[
            Text(_myTicket,
                style: GoogleFonts.jetBrainsMono(
                    color: Colors.white,
                    fontSize: 72,
                    fontWeight: FontWeight.w700,
                    height: 1.0)),
            const SizedBox(height: 4),
            Text(_myTicketHint(),
                style: TextStyle(
                    color: Colors.white.withOpacity(0.55), fontSize: 12)),
          ],
        ]),
      ]),
    );
  }

  String _myTicketHint() {
    final myItem = _findMyItem();
    if (myItem == null) return 'Keep this number with you';
    switch (myItem.status) {
      case 'done':
        return ' You have been served';
      case 'skipped':
        return ' Your number was skipped';
      case 'serving':
        return ' Your turn — please proceed now!';
      default:
        return 'Keep this number with you';
    }
  }

  // ── Status Banners ───────────────────────────────────────────────────────────
  Widget _buildStatusBanners() {
    final myItem = _findMyItem();
    if (_myTicket.isEmpty || myItem == null) return const SizedBox.shrink();

    final waiting = _queue.where((q) => q.status == 'waiting').toList();
    final ahead = waiting
        .where((q) =>
            q.number < myItem.number && q.department == myItem.department)
        .length;

    if (myItem.status == 'done') {
      return _StatusBanner(
        color: const Color(0xFFC8E6C9),
        borderColor: kGreen,
        icon: '/',
        title: 'You Have Been Served!',
        titleColor: const Color(0xFF1B5E20),
        message:
            'Your ticket ${_myTicket} has been served at ${myItem.deptLabel}. Thank you!',
        msgColor: const Color(0xFF2E7D32),
      );
    }

    if (myItem.status == 'serving') {
      return _StatusBanner(
        color: const Color(0xFFFFE0B2),
        borderColor: kAmber,
        icon: '!',
        title: 'Get Ready — It\'s Your Turn!',
        titleColor: const Color(0xFF7C4400),
        message: ' Please proceed to the ${myItem.deptLabel} counter now.',
        msgColor: const Color(0xFFA05A00),
        shake: true,
      );
    }

    if (myItem.status == 'waiting' && ahead <= 10 && ahead > 0) {
      return _StatusBanner(
        color: const Color(0xFFFFE0B2),
        borderColor: kAmber,
        icon: '!',
        title: 'Get Ready — Almost Your Turn!',
        titleColor: const Color(0xFF7C4400),
        message:
            'You are $ahead number${ahead == 1 ? '' : 's'} away. Head to ${myItem.deptLabel} now!',
        msgColor: const Color(0xFFA05A00),
      );
    }

    if (myItem.status == 'skipped') {
      return _StatusBanner(
        color: const Color(0xFFFFEBEE),
        borderColor: kRed,
        icon: 'X',
        title: 'Your Number Was Skipped',
        titleColor: const Color(0xFF7F0000),
        message: 'Please check with the staff.',
        msgColor: const Color(0xFFB71C1C),
      );
    }

    return const SizedBox.shrink();
  }

  // ── Dept Serving Grid ────────────────────────────────────────────────────────
  Widget _buildDeptServingGrid() {
    return Column(
        children: kDepts.map((d) {
      final key = d['key']!;
      final label = d['label']!;
      final serving = _queue.firstWhereOrNull(
          (q) => q.status == 'serving' && q.department == key);
      final waitCount = _queue
          .where((q) => q.status == 'waiting' && q.department == key)
          .length;
      final color = _deptColor(key);

      return Container(
        margin: const EdgeInsets.only(top: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border(left: BorderSide(color: color, width: 4)),
          boxShadow: [
            BoxShadow(
              color: Color(0x143B82F6),
              blurRadius: 20,
              offset: Offset(0, 8),
            )
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: kText3)),
              const SizedBox(height: 2),
              Text(
                serving?.ticketId ?? '—',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: kNavy,
                    height: 1.0),
              ),
            ]),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(waitCount.toString(),
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: kAmber)),
              const Text('WAITING',
                  style:
                      TextStyle(fontSize: 10, letterSpacing: 1, color: kText3)),
            ]),
          ],
        ),
      );
    }).toList());
  }

  // ── Queue List ───────────────────────────────────────────────────────────────
  // Each department gets its own card with an internal (max 10-row-tall)
  // scrollable list. While tracking a ticket, only that ticket's department
  // card is shown — the other two are hidden entirely.
  Widget _buildQueueSection() {
    final myDept = _deptFromTicket(_myTicket);
    final deptsToShow =
        myDept == null ? kDepts : kDepts.where((d) => d['key'] == myDept);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('WAITING QUEUE',
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: kText3)),
      const SizedBox(height: 10),
      ...deptsToShow.map((d) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildDeptQueueCard(d),
          )),
    ]);
  }

  Widget _buildDeptQueueCard(Map<String, String> dept) {
    final key = dept['key']!;
    final waiting = _queue
        .where((q) => q.status == 'waiting' && q.department == key)
        .toList()
      ..sort((a, b) => a.number.compareTo(b.number));

    const double rowHeight = 62;
    final listHeight = (waiting.length > 10 ? 10 : waiting.length) * rowHeight;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: _deptColor(key), width: 4)),
        boxShadow: [
          BoxShadow(
            color: Color(0x143B82F6),
            blurRadius: 20,
            offset: Offset(0, 8),
          )
        ],
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(dept['short']!,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: kNavy)),
              Text('${waiting.length} waiting',
                  style: const TextStyle(fontSize: 11, color: kText3)),
            ],
          ),
        ),
        if (waiting.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Text('No one waiting in this department.',
                style: TextStyle(color: kText3, fontSize: 13)),
          )
        else
          SizedBox(
            height: listHeight,
            child: Scrollbar(
              thumbVisibility: true,
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: waiting.length,
                itemBuilder: (context, idx) {
                  final item = waiting[idx];
                  final isMe = item.ticketId == _myTicket ||
                      item.number.toString().padLeft(3, '0') == _myTicket;
                  return _QueueListItem(
                    item: item,
                    idx: idx,
                    isMe: isMe,
                    isNext: idx == 0,
                  );
                },
              ),
            ),
          ),
      ]),
    );
  }

  // ── Track Section ────────────────────────────────────────────────────────────
  Widget _buildTrackSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Color(0x143B82F6),
            blurRadius: 20,
            offset: Offset(0, 8),
          )
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('TRACK MY NUMBER',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                color: kText3)),
        const SizedBox(height: 10),
        if (_myTicket.isEmpty) ...[
          Row(children: [
            Expanded(
              child: TextField(
                controller: _ticketCtrl,
                textCapitalization: TextCapitalization.characters,
                textAlign: TextAlign.center,
                maxLength: 4,
                inputFormatters: [
                  // Blocks emojis/symbols — only plain letters & digits allowed.
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                ],
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 22, fontWeight: FontWeight.w700, color: kNavy),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'e.g. R001',
                  hintStyle:
                      GoogleFonts.jetBrainsMono(fontSize: 18, color: kText3),
                  filled: true,
                  fillColor: Color(0xFFF5F8FF),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: kIvory2, width: 2)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: kIvory2, width: 2)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: kNavy, width: 2)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                ),
                onSubmitted: (_) => _handleTrackPressed(),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _handleTrackPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF4F8EF7),
                  foregroundColor: Color(0xFFF5F8FF),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                ),
                child: const Text('Track',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            ),
          ]),
        ] else ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F8FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kIvory2, width: 2),
            ),
            child: Row(children: [
              Expanded(
                child: Text('Tracking $_myTicket',
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: kNavy)),
              ),
              GestureDetector(
                onTap: _clearMyTicket,
                child: const Text('Clear',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: kText3,
                        decoration: TextDecoration.underline)),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  // ── Footer ───────────────────────────────────────────────────────────────────
  Widget _buildFooter() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: kNavy.withOpacity(0.06), blurRadius: 12)],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: const Center(
        child: Text('Quelio', style: TextStyle(color: kText3, fontSize: 12)),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

// A single blinking dot: green + soft pulsing glow when connected to the
// database, grey/static when not. Replaces the old "LIVE" and "Firebase"
// text pills.
class _ConnectionDot extends StatefulWidget {
  final bool connected;
  const _ConnectionDot({required this.connected});
  @override
  State<_ConnectionDot> createState() => _ConnectionDotState();
}

class _ConnectionDotState extends State<_ConnectionDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _blink;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _blink = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.connected ? kGreen : const Color(0xFFB0B8C4);
    return AnimatedBuilder(
      animation: _blink,
      builder: (_, __) {
        final opacity = widget.connected ? _blink.value : 1.0;
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(opacity),
            boxShadow: widget.connected
                ? [
                    BoxShadow(
                      color: kGreen.withOpacity(opacity * 0.6),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
        );
      },
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final Color color, borderColor;
  final String icon, title, message;
  final Color titleColor, msgColor;
  final bool shake;
  const _StatusBanner({
    required this.color,
    required this.borderColor,
    required this.icon,
    required this.title,
    required this.message,
    required this.titleColor,
    required this.msgColor,
    this.shake = false,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [color, color.withOpacity(0.6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        border: Border.all(color: borderColor, width: 2),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(icon, style: const TextStyle(fontSize: 26)),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: titleColor)),
          const SizedBox(height: 2),
          Text(message,
              style: TextStyle(fontSize: 12, color: msgColor, height: 1.4)),
        ])),
      ]),
    );
  }
}

class _QueueListItem extends StatelessWidget {
  final QueueItem item;
  final int idx;
  final bool isMe, isNext;
  const _QueueListItem({
    required this.item,
    required this.idx,
    required this.isMe,
    required this.isNext,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isMe
            ? kNavy.withOpacity(0.04)
            : isNext
                ? kGreen.withOpacity(0.04)
                : Colors.transparent,
        border: const Border(
            bottom: BorderSide(color: Color(0xFFEDE6D8), width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              item.ticketId.isNotEmpty
                  ? item.ticketId + (isMe ? ' ← You' : '')
                  : item.pad3 + (isMe ? ' ← You' : ''),
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isMe ? kGold : kNavy),
            ),
            Text(
              '${item.deptLabel.isNotEmpty ? item.deptLabel + ' · ' : ''}Issued ${item.issuedAt}',
              style: const TextStyle(fontSize: 11, color: kText3),
            ),
          ]),
          Text(
            isNext ? 'Next up' : '${idx + 1} away',
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: kText3),
          ),
        ],
      ),
    );
  }
}

// ── QR Scanner Sheet ──────────────────────────────────────────────────────────
class _QrScannerSheet extends StatefulWidget {
  final void Function(String ticketId) onScanned;
  const _QrScannerSheet({required this.onScanned});
  @override
  State<_QrScannerSheet> createState() => _QrScannerSheetState();
}

class _QrScannerSheetState extends State<_QrScannerSheet> {
  final MobileScannerController _scanCtrl = MobileScannerController();
  bool _scanned = false;

  String? _extract(String raw) {
    final trimmed = raw.trim().toUpperCase();
    final plain = RegExp(r'^([RAS]\d{3})$').firstMatch(trimmed);
    if (plain != null) return plain.group(1);
    try {
      final uri = Uri.parse(raw);
      final t = uri.queryParameters['ticket'];
      if (t != null && t.isNotEmpty) return t.toUpperCase();
    } catch (_) {}
    try {
      // simple JSON check
      if (raw.contains('ticketId')) {
        final re = RegExp(r'"ticketId"\s*:\s*"([^"]+)"');
        final m = re.firstMatch(raw);
        if (m != null) return m.group(1)!.toUpperCase();
      }
    } catch (_) {}
    return null;
  }

  @override
  void dispose() {
    _scanCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        const Text(' Scan Your Ticket QR Code',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: kNavy)),
        const SizedBox(height: 16),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(children: [
              MobileScanner(
                controller: _scanCtrl,
                onDetect: (capture) {
                  if (_scanned) return;
                  final barcodes = capture.barcodes;
                  for (final b in barcodes) {
                    final raw = b.rawValue ?? '';
                    final tid = _extract(raw);
                    if (tid != null) {
                      _scanned = true;
                      Navigator.of(context).pop();
                      widget.onScanned(tid);
                      return;
                    }
                  }
                },
              ),
              // Scan line
              _ScanLine(),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        const Text('Point your camera at the QR code on your ticket',
            style: TextStyle(fontSize: 12, color: kText3)),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFF4F8EF7),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: const Text('Cancel',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ),
      ]),
    );
  }
}

class _ScanLine extends StatefulWidget {
  @override
  State<_ScanLine> createState() => _ScanLineState();
}

class _ScanLineState extends State<_ScanLine>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.1, end: 0.88)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Positioned(
        top: _anim.value * (MediaQuery.of(context).size.height * 0.5 - 20),
        left: 20,
        right: 20,
        child: Container(
          height: 2,
          decoration: BoxDecoration(
            color: kGreen,
            boxShadow: [
              BoxShadow(color: kGreen.withOpacity(0.7), blurRadius: 8)
            ],
          ),
        ),
      ),
    );
  }
}

// ── Toast overlay ─────────────────────────────────────────────────────────────
class _ToastWidget extends StatefulWidget {
  final String msg;
  final bool isOk, isError;
  final VoidCallback onDone;
  const _ToastWidget({
    required this.msg,
    required this.isOk,
    required this.isError,
    required this.onDone,
  });
  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300))
      ..forward();
    Future.delayed(const Duration(milliseconds: 3500), () {
      if (mounted) _ctrl.reverse().then((_) => widget.onDone());
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.isOk
        ? kGreen
        : widget.isError
            ? kRed
            : kGold;
    return Positioned(
      bottom: 24,
      left: 20,
      right: 20,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
            .animate(_ctrl),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            decoration: BoxDecoration(
              color: kNavy,
              borderRadius: BorderRadius.circular(12),
              border: Border(left: BorderSide(color: borderColor, width: 4)),
              boxShadow: [
                BoxShadow(
                    color: kNavy.withOpacity(0.3),
                    blurRadius: 24,
                    offset: const Offset(0, 8))
              ],
            ),
            child: Text(widget.msg,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
          ),
        ),
      ),
    );
  }
}

// ── List extension ────────────────────────────────────────────────────────────
extension ListOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
