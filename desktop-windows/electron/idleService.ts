import { powerMonitor } from "electron";

export class IdleService {
  private thresholdSeconds: number;
  private pollTimer: NodeJS.Timeout | null = null;
  private didFireForCurrentIdlePeriod = false;

  private readonly onSystemPause = () => {
    this.onShouldAutoPause();
  };

  constructor(
    idleTimeoutMinutes: number,
    private readonly onShouldAutoPause: () => void
  ) {
    this.thresholdSeconds = Math.max(60, idleTimeoutMinutes * 60);
  }

  updateThreshold(minutes: number): void {
    this.thresholdSeconds = Math.max(60, minutes * 60);
    this.didFireForCurrentIdlePeriod = false;
  }

  start(): void {
    powerMonitor.on("suspend", this.onSystemPause);
    powerMonitor.on("lock-screen", this.onSystemPause);

    this.stopPolling();
    this.pollTimer = setInterval(() => {
      const idleSeconds = powerMonitor.getSystemIdleTime();
      if (idleSeconds >= this.thresholdSeconds) {
        if (!this.didFireForCurrentIdlePeriod) {
          this.didFireForCurrentIdlePeriod = true;
          this.onShouldAutoPause();
        }
      } else {
        this.didFireForCurrentIdlePeriod = false;
      }
    }, 5000);
  }

  stop(): void {
    this.stopPolling();
    powerMonitor.off("suspend", this.onSystemPause);
    powerMonitor.off("lock-screen", this.onSystemPause);
  }

  private stopPolling(): void {
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = null;
    }
  }
}
