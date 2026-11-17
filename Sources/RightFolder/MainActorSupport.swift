import Foundation

/// Runs `body` synchronously on the main actor from a callback that is already executing on the
/// main thread. `MainActor.assumeIsolated` exists only on macOS 14+, so macOS 13 uses a shim.
///
/// `@MainActor` is a compile-time attribute and does not change a closure's calling convention,
/// so casting to a plain closure and calling it on the main thread is safe here. Every caller is
/// a main-thread callback (a main run loop source, a main queue, or the app event target).
@inline(__always)
func assumeMainActor<T>(_ body: @MainActor () -> T) -> T {
    if #available(macOS 14, *) {
        return MainActor.assumeIsolated(body)
    }
    return withoutActuallyEscaping(body) { escaping in
        unsafeBitCast(escaping, to: (() -> T).self)()
    }
}
