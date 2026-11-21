import 'dart:ffi';
import 'dart:io';

typedef _InitializeNative = IntPtr Function(Pointer<Void>);
typedef _InitializeDart = int Function(Pointer<Void>);

void initializeNativeEngine() {
  if (!Platform.isLinux) return;
  final library = DynamicLibrary.process();
  const symbol = 'fl_engine_initialize_dart_api_dl';
  if (!library.providesSymbol(symbol)) return;
  final initialize = library.lookupFunction<_InitializeNative, _InitializeDart>(
    symbol,
  );
  final result = initialize(NativeApi.initializeApiDLData);
  if (result != 0) {
    throw StateError('Native Linux engine initialization failed: $result');
  }
}
