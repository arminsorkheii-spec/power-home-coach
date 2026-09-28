"use client";

function printableCss() {
  const rules: string[] = [];
  for (const sheet of Array.from(document.styleSheets)) {
    try {
      for (const rule of Array.from(sheet.cssRules)) {
        if (rule instanceof CSSMediaRule && rule.conditionText.includes("print")) {
          rules.push(...Array.from(rule.cssRules).map((item) => item.cssText));
        }
      }
    } catch {
      // Ignore browser-managed stylesheets that do not expose their rules.
    }
  }
  return rules.join("\n");
}

function safeFilename(value: string) {
  return value.trim().replace(/[\\/:*?"<>|]+/g, "-").replace(/\s+/g, " ") || "program";
}

async function waitForImages(root: ParentNode) {
  await Promise.all(
    Array.from(root.querySelectorAll<HTMLImageElement>("img")).map(async (image) => {
      if (image.complete) return image.decode().catch(() => undefined);
      await new Promise<void>((resolve) => {
        const timeout = window.setTimeout(resolve, 10_000);
        image.addEventListener("load", () => resolve(), { once: true });
        image.addEventListener("error", () => resolve(), { once: true });
        image.addEventListener("load", () => window.clearTimeout(timeout), { once: true });
        image.addEventListener("error", () => window.clearTimeout(timeout), { once: true });
      });
    }),
  );
}

async function deliverPdf(blob: Blob, filename: string) {
  const downloadName = `${safeFilename(filename)}.pdf`;
  const file = new File([blob], downloadName, { type: "application/pdf" });
  const shareNavigator = navigator as Navigator & {
    canShare?: (data: ShareData) => boolean;
    share?: (data: ShareData) => Promise<void>;
  };

  if (shareNavigator.share && shareNavigator.canShare?.({ files: [file] })) {
    try {
      await shareNavigator.share({ files: [file], title: downloadName });
      return;
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError") return;
    }
  }

  const url = URL.createObjectURL(blob);
  const appleMobile = /iPad|iPhone|iPod/.test(navigator.userAgent) ||
    (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
  const standalone = window.matchMedia("(display-mode: standalone)").matches ||
    Boolean((navigator as Navigator & { standalone?: boolean }).standalone);

  if (appleMobile && standalone) {
    window.location.assign(url);
  } else {
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = downloadName;
    anchor.rel = "noopener";
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
  }
  window.setTimeout(() => URL.revokeObjectURL(url), 60_000);
}

export async function downloadPlanPdf(elementId: string, filename: string) {
  const source = document.getElementById(elementId);
  if (!source) throw new Error("نسخهٔ قابل دانلود برنامه پیدا نشد.");

  const frame = document.createElement("iframe");
  frame.setAttribute("aria-hidden", "true");
  frame.style.position = "fixed";
  frame.style.inset = "0 auto auto -10000px";
  frame.style.width = "794px";
  frame.style.height = "1123px";
  frame.style.border = "0";
  frame.style.opacity = "0";
  frame.style.pointerEvents = "none";
  document.body.appendChild(frame);

  try {
    const frameDocument = frame.contentDocument;
    if (!frameDocument) throw new Error("آماده‌سازی PDF انجام نشد.");
    frameDocument.open();
    frameDocument.write(`<!doctype html><html dir="rtl"><head><base href="${location.origin}/"><meta charset="utf-8"><style>
      @font-face{font-family:CoachArabic;src:url('/fonts/NotoSansArabic-Regular.ttf') format('truetype');font-weight:400;font-display:swap}
      @font-face{font-family:CoachArabic;src:url('/fonts/NotoSansArabic-Bold.ttf') format('truetype');font-weight:700 900;font-display:swap}
      *{box-sizing:border-box}html,body{margin:0;width:794px;background:#fff;color:#111214;font-family:CoachArabic,Tahoma,Arial,sans-serif}
      ${printableCss()}
      .print-shell{display:block!important;width:794px!important;min-height:1123px!important;padding:38px!important;background:#fff!important;color:#111214!important}
      .coach-contacts{display:flex!important;align-items:center!important;gap:14px!important;flex-wrap:wrap!important;margin-top:9px!important}
      .coach-contacts a{display:inline-flex!important;align-items:center!important;gap:6px!important;color:#d7d8db!important;text-decoration:none!important;font:10px Arial,sans-serif!important;line-height:1!important}
      .coach-contacts>a>span:first-child{display:inline-grid!important;width:20px!important;height:20px!important;min-width:20px!important;max-width:20px!important;min-height:20px!important;max-height:20px!important;place-items:center!important;overflow:hidden!important;border-radius:6px!important;padding:2px!important}
      .coach-contacts .contact-label{display:inline!important;width:auto!important;height:auto!important;min-width:0!important;max-width:none!important;min-height:0!important;max-height:none!important;padding:0!important;background:none!important}
      .coach-contacts svg{display:block!important;width:16px!important;height:16px!important;max-width:16px!important;max-height:16px!important}
      .instagram-logo{background:linear-gradient(35deg,#feda75,#fa7e1e,#d62976,#962fbf,#4f5bd5)!important}.whatsapp-logo{background:#25d366!important}
      img{image-rendering:auto!important}
      .print-superset-group{border:2px solid #111214!important;border-radius:8px!important;padding:5px!important;background:#fff!important;break-inside:avoid-page!important;page-break-inside:avoid!important}
      .print-superset-title{background:#111214!important;color:#fff!important}
    </style></head><body>${source.outerHTML}</body></html>`);
    frameDocument.close();
    await Promise.race([
      frameDocument.fonts.ready,
      new Promise<void>((resolve) => window.setTimeout(resolve, 8_000)),
    ]);
    await waitForImages(frameDocument);

    const printable = frameDocument.querySelector<HTMLElement>(".print-shell");
    if (!printable) throw new Error("محتوای PDF آماده نشد.");
    const [{ default: html2canvas }, { jsPDF }] = await Promise.all([
      import("html2canvas"),
      import("jspdf"),
    ]);
    const canvas = await html2canvas(printable, {
      backgroundColor: "#ffffff",
      scale: 2.5,
      useCORS: true,
      allowTaint: false,
      imageTimeout: 20_000,
      logging: false,
      windowWidth: 794,
    });

    const pdf = new jsPDF({ orientation: "portrait", unit: "mm", format: "a4", compress: true });
    const pageHeightPx = Math.floor((canvas.width * 297) / 210);
    const domHeight = Math.max(printable.scrollHeight, printable.getBoundingClientRect().height);
    const canvasScaleY = canvas.height / Math.max(1, domHeight);
    const printableTop = printable.getBoundingClientRect().top;
    const breakSelectors = [
      ".print-superset-group", ".print-exercise-unit", ".print-meal", ".print-supplement", ".print-day-title",
      ".print-brand", ".print-client", ".print-macros", ".print-superset-title",
    ].join(",");
    const safeBreaks = Array.from(frameDocument.querySelectorAll<HTMLElement>(breakSelectors))
      .flatMap((element) => {
        const rect = element.getBoundingClientRect();
        return [rect.top - printableTop, rect.bottom - printableTop];
      })
      .filter((value) => value > 0 && value < domHeight)
      .map((value) => Math.round(value * canvasScaleY))
      .sort((a, b) => a - b);

    let offset = 0;
    let page = 0;
    while (offset < canvas.height) {
      const desiredEnd = Math.min(offset + pageHeightPx, canvas.height);
      let end = desiredEnd;
      if (desiredEnd < canvas.height) {
        const candidates = safeBreaks.filter((value) => value > offset + pageHeightPx * 0.55 && value <= desiredEnd - 10);
        if (candidates.length) end = candidates[candidates.length - 1];
      }
      if (end <= offset + 40) end = desiredEnd;
      const sliceHeight = Math.min(end - offset, canvas.height - offset);
      const slice = document.createElement("canvas");
      slice.width = canvas.width;
      slice.height = sliceHeight;
      const context = slice.getContext("2d");
      if (!context) throw new Error("ساخت صفحه PDF انجام نشد.");
      context.fillStyle = "#ffffff";
      context.fillRect(0, 0, slice.width, slice.height);
      context.drawImage(canvas, 0, offset, canvas.width, sliceHeight, 0, 0, canvas.width, sliceHeight);
      if (page > 0) pdf.addPage();
      pdf.addImage(slice.toDataURL("image/jpeg", 0.98), "JPEG", 0, 0, 210, (sliceHeight / canvas.width) * 210, undefined, "SLOW");
      offset = end;
      page += 1;
    }

    await deliverPdf(pdf.output("blob"), filename);
  } finally {
    frame.remove();
  }
}
