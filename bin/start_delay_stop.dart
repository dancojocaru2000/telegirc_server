class StartDelayStop {
  final Function startAction;
  final Function stopAction;
  final Duration delay;
  final bool callStartIfNotStopped;

  int _expectedOp = 0;

  StartDelayStop({
    required this.startAction,
    required this.stopAction,
    required this.delay,
    this.callStartIfNotStopped = true,
  });

  void start() {
    if (_expectedOp != 0) {
      if (callStartIfNotStopped) {
        startAction();
      }
    }
    else {
      startAction();
    }

    _expectedOp++;
    final thisOpId = _expectedOp;
    Future.delayed(delay).then((_) => _stop(thisOpId));
  }

  void _stop(int opId) {
    if (opId != _expectedOp) {
      return;
    }

    stopAction();

    _expectedOp = 0;
  }

  void stop() {
    if (_expectedOp != 0) {
      _stop(_expectedOp);
    }
  }
}