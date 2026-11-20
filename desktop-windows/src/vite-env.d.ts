/// <reference types="vite/client" />
import type { WorkLogBridge } from "../electron/preload";

declare global {
  interface Window {
    worklog: WorkLogBridge;
  }
}

export {};
