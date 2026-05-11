/// sing-box 核心服务状态
sealed class BoxStatus {
  const BoxStatus();
}

class BoxStopped extends BoxStatus {
  const BoxStopped();
}

class BoxStarting extends BoxStatus {
  const BoxStarting();
}

class BoxStarted extends BoxStatus {
  const BoxStarted();
}

class BoxStopping extends BoxStatus {
  const BoxStopping();
}
