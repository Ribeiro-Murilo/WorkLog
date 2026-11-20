import { globalShortcut } from "electron";
import type { ShortcutAction } from "../src/shared/types";
import type { ShortcutRepository } from "./services/shortcutRepository";

export type ShortcutHandlers = Record<ShortcutAction, () => void>;

export class ShortcutsService {
  constructor(
    private readonly shortcutRepository: ShortcutRepository,
    private readonly handlers: ShortcutHandlers
  ) {}

  registerAll(): void {
    globalShortcut.unregisterAll();
    const bindings = this.shortcutRepository.ensureDefaults();
    for (const binding of bindings) {
      if (!binding.isEnabled || !binding.accelerator) continue;
      const handler = this.handlers[binding.action];
      if (!handler) continue;
      try {
        globalShortcut.register(binding.accelerator, handler);
      } catch {
        // Ignora atalho reservado pelo sistema operacional sem interromper o app.
      }
    }
  }

  updateBinding(action: ShortcutAction, accelerator: string, isEnabled = true): void {
    this.shortcutRepository.upsert(action, accelerator, isEnabled);
    this.registerAll();
  }

  unregisterAll(): void {
    globalShortcut.unregisterAll();
  }
}
