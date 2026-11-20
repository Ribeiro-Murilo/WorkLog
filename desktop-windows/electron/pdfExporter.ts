import { BrowserWindow } from "electron";
import fs from "node:fs";

export async function renderHtmlToPdf(html: string, outputPath: string): Promise<void> {
  const win = new BrowserWindow({
    show: false,
    width: 794,
    height: 1123,
    webPreferences: {
      sandbox: true,
      contextIsolation: true,
      nodeIntegration: false
    }
  });

  try {
    await win.loadURL(`data:text/html;charset=utf-8,${encodeURIComponent(html)}`);
    const buffer = await win.webContents.printToPDF({
      pageSize: "A4",
      printBackground: true,
      margins: {
        top: 0,
        bottom: 0,
        left: 0,
        right: 0
      }
    });
    fs.writeFileSync(outputPath, buffer);
  } finally {
    if (!win.isDestroyed()) {
      win.destroy();
    }
  }
}
