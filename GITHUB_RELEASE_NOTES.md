# WorkLog v0.1.1 Release Notes

This release focuses on the exported PDF documents (reports and billing invoices), giving them a professional, client-ready design and fixing a rendering bug.

## Bug Fixes

- Fixed the report/invoice title being clipped at the top of the PDF. The document was rendered on the default US Letter page while the layout assumed A4, pushing the header above the real page edge. The PDF now uses a proper A4 media box.

## PDF Redesign

- Redesigned the invoice and report PDFs with a professional, client-ready layout.
- Two-column letterhead: issuer/title on the left, invoice metadata (number, issue date, billing period) aligned on the right, separated by a brand accent rule.
- Clean "ledger" style table: brand-colored uppercase headers with an accent underline, thin row separators, no vertical grid lines, and no heavy zebra striping.
- Tabular (monospaced) figures so durations and currency values align cleanly.
- Emphasized total row with an accent tint and highlighted totals.
- Refined footer with a divider, optional note on the left, and app name plus page number on the right.
- Introduced a restrained brand accent color used across headers, rules, and totals.

## Optional App Logo in PDFs

- Added an option to include the app logo in exported PDFs (both reports and invoices).
- The logo is placed at the top-left, leading the letterhead, with rounded corners.
- Optional and off by default. Toggle it in Settings → General ("Incluir logo do app nos PDFs").

## Version

- Bumped app version to 0.1.1.
