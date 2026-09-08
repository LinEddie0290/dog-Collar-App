/// Connection state of the collar link, surfaced to the UI so it can show
/// "connected / reconnecting / offline" without knowing anything about sockets.
enum ConnStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
}
