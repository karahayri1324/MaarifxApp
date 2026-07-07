import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../../config/app_config.dart';
import '../../config/theme.dart';
import '../../services/audio_service.dart';

/// PlayerScreen'den dönen takip-turu verisi.
/// - Ekran görüntüsüyle soru (legacy): imageFile + text.
/// - İşaretli bölge (kalem): markedRegion [x1,y1,x2,y2] 0-1000 + text (not).
/// - Hint yanıtı: hintRef + text (yanıt); skip=true ise "Cevap vermek istemiyorum".
class AnnotationResult {
  final File? imageFile;
  final String text;
  final List<int>? markedRegion;
  final String? hintRef;
  final bool skip;

  AnnotationResult({
    this.imageFile,
    this.text = '',
    this.markedRegion,
    this.hintRef,
    this.skip = false,
  });
}

class PlayerScreen extends StatefulWidget {
  final String requestId;
  final String token;
  final bool isLive;
  final String? imageUrl;
  final String title;

  const PlayerScreen({
    super.key,
    required this.requestId,
    required this.token,
    this.isLive = false,
    this.imageUrl,
    this.title = 'Çözüm',
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final WebViewController _webViewController;
  final AudioService _audioService = AudioService();

  // UI state
  bool _isLoading = true;

  // Playback state
  bool _isPlaying = false;
  bool _hasEnded = false;
  double _speed = 1.0;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initWebView();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _audioService.stop();
    _audioService.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ─── WebView ────────────────────────────────────────

  void _initWebView() {
    final url = widget.isLive
        ? AppConfig.canvasLiveUrl(widget.requestId, widget.token, widget.imageUrl)
        : AppConfig.canvasReplayUrl(widget.requestId, widget.token);

    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('FlutterChannel', onMessageReceived: _onJsMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _isLoading = false);
        },
        onWebResourceError: (error) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _errorMessage = 'Sayfa yuklenemedi: ${error.description}';
            });
          }
        },
      ))
      ..loadRequest(Uri.parse(url));

    // Allow audio autoplay without user gesture (Android)
    final platform = _webViewController.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
  }

  // ─── JS Messages ───────────────────────────────────

  void _onJsMessage(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      final event = data['event'] as String? ?? '';
      switch (event) {
        case 'imageLoaded':
          _handleImageLoaded(data);
        case 'timeUpdate':
          _handleTimeUpdate(data);
        case 'audioPlay':
          _handleAudioPlay(data);
        case 'audioPause':
          _audioService.pause();
        case 'audioSeek':
          _audioService.seek((data['time'] as num?)?.toInt() ?? 0);
        case 'ended':
          if (mounted) setState(() { _hasEnded = true; _isPlaying = false; });
          _audioService.pause();
        case 'error':
          if (mounted) setState(() => _errorMessage = data['message'] as String? ?? 'Hata');
        case 'ready':
          if (mounted) setState(() => _isLoading = false);
        case 'annotationSend':
          _handleAnnotationSend(data);
        case 'markedContent':
          _handleMarkedContent(data);
        case 'hintAnswer':
          _handleHintAnswer(data);
        case 'closeRequest':
          // Canvas icindeki "Çözüme Bak" butonu — X'e basmakla ayni: ekrani kapat
          if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('[Player] JS parse error: $e');
    }
  }

  Future<void> _handleAnnotationSend(Map<String, dynamic> data) async {
    final base64Str = data['screenshotBase64'] as String? ?? '';
    final text = data['text'] as String? ?? '';
    if (base64Str.isEmpty && text.isEmpty) return;

    try {
      // Save base64 as temp file (boş base64 → boş/bozuk görsel gönderme)
      File? tempFile;
      if (base64Str.isNotEmpty) {
        final Uint8List bytes = base64Decode(base64Str);
        final tempDir = await getTemporaryDirectory();
        tempFile = File(
          '${tempDir.path}/annotation_${DateTime.now().millisecondsSinceEpoch}.png',
        );
        await tempFile.writeAsBytes(bytes);
      }

      // Pop with result
      if (mounted) {
        Navigator.of(context).pop(
          AnnotationResult(imageFile: tempFile, text: text),
        );
      }
    } catch (e) {
      debugPrint('[Player] Annotation save error: $e');
    }
  }

  // İşaretli bölge (canvas kalemle): markedRegion [x1,y1,x2,y2] 0-1000 + not.
  // Backend bunu önceki tur DSL'inden <isaretli_icerik>'e çözer; not → <ogrenci_sorusu>.
  void _handleMarkedContent(Map<String, dynamic> data) {
    final note = data['note'] as String? ?? '';
    final raw = data['markedRegion'];
    List<int>? region;
    if (raw is List && raw.length == 4) {
      region = raw.map((e) => (e as num).toInt()).toList();
    }
    if (region == null) return;
    if (mounted) {
      Navigator.of(context).pop(AnnotationResult(text: note, markedRegion: region));
    }
  }

  // Hint yanıtı: hintRef + text (yanıt). skip=true → canvas zaten "Cevap vermek istemiyorum" yollar.
  void _handleHintAnswer(Map<String, dynamic> data) {
    final hintRef = data['hintRef'] as String? ?? '';
    final text = data['text'] as String? ?? '';
    final skip = data['skip'] as bool? ?? false;
    if (mounted) {
      Navigator.of(context).pop(
        AnnotationResult(text: text, hintRef: hintRef.isNotEmpty ? hintRef : null, skip: skip),
      );
    }
  }

  void _handleImageLoaded(Map<String, dynamic> data) {
    if (!mounted) return;
    final w = (data['width'] as num?)?.toInt() ?? 0;
    final h = (data['height'] as num?)?.toInt() ?? 0;
    if (w > 0 && h > 0) {
      setState(() => _isLoading = false);
      if (w > h) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight,
        ]);
      } else {
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      }
    }
  }

  void _handleTimeUpdate(Map<String, dynamic> data) {
    if (!mounted) return;
    final ct = (data['currentTime'] as num?)?.toDouble() ?? 0;
    if (!_isPlaying && ct > 0 && !_hasEnded) {
      setState(() => _isPlaying = true);
    }
  }

  void _handleAudioPlay(Map<String, dynamic> data) {
    final url = data['url'] as String?;
    if (url != null && url.isNotEmpty) {
      _audioService.play(url, startTimeMs: (data['startTime'] as num?)?.toInt() ?? 0);
      _audioService.setSpeed(_speed);
    }
  }

  // ─── Controls ───────────────────────────────────────

  void _togglePlayPause() {
    if (_hasEnded) {
      _webViewController.runJavaScript('MaarifX.seek(0); MaarifX.play();');
      setState(() { _hasEnded = false; _isPlaying = true; });
      _audioService.seek(0);
    } else if (_isPlaying) {
      _webViewController.runJavaScript('MaarifX.pause();');
      setState(() => _isPlaying = false);
      _audioService.pause();
    } else {
      _webViewController.runJavaScript('MaarifX.play();');
      setState(() => _isPlaying = true);
    }
  }

  void _goBack() async {
    if (widget.isLive) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1C2129),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Canlı çözüm devam ediyor', style: TextStyle(color: Colors.white)),
          content: const Text('Çıkmak istediğinize emin misiniz?', style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Çık', style: TextStyle(color: AppTheme.danger)),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  // ─── Build ──────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // WebView
          WebViewWidget(controller: _webViewController),

          // Loading
          if (_isLoading) _buildLoading(),

          // Error
          if (_errorMessage != null) _buildError(),

          // Ended overlay (replay)
          if (_hasEnded && !widget.isLive) _buildEndedOverlay(),

          // Top gradient (visual only – does NOT block WebView touches)
          Positioned(
            top: 0, left: 0, right: 0,
            child: IgnorePointer(
              child: Container(
                height: MediaQuery.of(context).padding.top + 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),

          // Back button (only this absorbs touches)
          Positioned(
            top: 0, left: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Material(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(24),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: _goBack,
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.arrow_back_rounded, color: Colors.white, size: 26),
                    ),
                  ),
                ),
              ),
            ),
          ),

        ],
      ),
    );
  }

  Widget _buildLoading() {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 40, height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
              ),
            ),
            SizedBox(height: 16),
            Text('Yükleniyor...', style: TextStyle(color: Colors.white54, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppTheme.danger, size: 56),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.white70, fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Geri Don'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEndedOverlay() {
    return Center(
      child: GestureDetector(
        onTap: _togglePlayPause,
        child: Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.primary,
            boxShadow: [
              BoxShadow(color: AppTheme.primary.withOpacity(0.4), blurRadius: 24, spreadRadius: 4),
            ],
          ),
          child: const Icon(Icons.replay_rounded, color: Colors.white, size: 40),
        ),
      ),
    );
  }


}
