import 'dart:async';
import 'dart:ffi';
import 'package:material_ui/material_ui.dart';
import 'package:tsumiru/src/utils/desktop/native_engine_io.dart';
import 'package:tsumiru/src/widgets/zoom/zoom_view.dart';

typedef NativeCallbackNative = Void Function(Int32);
typedef TestCallbackNative =
    Void Function(Pointer<NativeFunction<NativeCallbackNative>>, Int32);
typedef TestCallbackDart =
    void Function(Pointer<NativeFunction<NativeCallbackNative>>, int);

bool ffiCallbackExecuted = false;
int ffiCallbackReceivedValue = 0;

void _onNativeCallback(int value) {
  ffiCallbackExecuted = true;
  ffiCallbackReceivedValue = value;
  debugPrint(
    '[SAFE_PROBE] >>> Dart callback invoked from native IsolateScope with value $value <<<',
  );
}

void verifyFfiIsolateScope() {
  final dylib = DynamicLibrary.process();
  final testFn = dylib.lookupFunction<TestCallbackNative, TestCallbackDart>(
    'fl_test_ffi_isolate_scope_callback',
  );
  final cbPointer = Pointer.fromFunction<NativeCallbackNative>(
    _onNativeCallback,
  );
  testFn(cbPointer, 165);
  if (!ffiCallbackExecuted || ffiCallbackReceivedValue != 165) {
    throw StateError('FFI IsolateScope callback was not executed properly!');
  }
  debugPrint(
    '[SAFE_PROBE] FFI IsolateScope verification passed: callback received $ffiCallbackReceivedValue!',
  );
}

void main() {
  initializeNativeEngine();
  WidgetsFlutterBinding.ensureInitialized();
  if (DynamicLibrary.process().providesSymbol(
    'fl_test_ffi_isolate_scope_callback',
  )) {
    verifyFfiIsolateScope();
  }
  runApp(const SafeProbeApp());
}

class SafeProbeApp extends StatefulWidget {
  const SafeProbeApp({super.key});

  @override
  State<SafeProbeApp> createState() => _SafeProbeAppState();
}

class _SafeProbeAppState extends State<SafeProbeApp>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final ZoomViewController _zoomController = ZoomViewController();
  late final AnimationController _animController;
  Timer? _lifecycleTimer;
  int _frameCount = 0;
  DateTime? _startTime;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _animController.addListener(() {
      _frameCount++;
      if (_scrollController.hasClients) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        final offset = (_animController.value * maxScroll * 0.1) % maxScroll;
        _scrollController.jumpTo(offset);
      }
      if (_frameCount % 165 == 0) {
        final elapsed = DateTime.now().difference(_startTime!).inMilliseconds;
        final fps = elapsed > 0 ? (_frameCount * 1000.0 / elapsed) : 0.0;
        debugPrint(
          '[SAFE_PROBE] Flutter frames: $_frameCount, elapsed: ${elapsed}ms (${fps.toStringAsFixed(1)} FPS)',
        );
      }
    });
    if (const bool.fromEnvironment('TSUMIRU_NATIVE_CYCLE_TEST')) {
      final cycle = DynamicLibrary.process()
          .lookupFunction<Void Function(), void Function()>(
            'fl_test_cycle_surface',
          );
      _lifecycleTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (timer.tick >= 4) cycle();
        if (timer.tick >= 8) timer.cancel();
      });
    }
  }

  @override
  void dispose() {
    _lifecycleTimer?.cancel();
    _animController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: ZoomView(
          controller: _scrollController,
          zoomViewController: _zoomController,
          scrollAxis: Axis.vertical,
          reverse: false,
          minScale: 1.0,
          maxScale: 4.0,
          pinchEnabled: true,
          child: AnimatedBuilder(
            animation: _animController,
            builder: (context, child) {
              return ListView.builder(
                controller: _scrollController,
                itemCount: 200,
                itemBuilder: (context, index) {
                  return Container(
                    height: 250,
                    margin: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 8,
                    ),
                    decoration: BoxDecoration(
                      color: index.isEven
                          ? const Color(0xFF1E1E1E)
                          : const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.blueAccent.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Page $index [High-Refresh Wayland Subsurface]',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Frame: $_frameCount (Tick: ${_animController.value.toStringAsFixed(3)})',
                            style: const TextStyle(
                              color: Colors.cyanAccent,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
