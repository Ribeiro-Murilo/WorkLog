# WorkLog Release Notes

This release introduces the core WorkLog experience for tracking project time, reviewing productivity, generating reports, and preparing billing documents from completed work sessions.

## Summary

- Native dashboard organized with a macOS sidebar and a dedicated Summary view.
- Time totals for today, the current week, the current month, and all tracked time.
- Active and archived project counters.
- Recent session list for quickly reviewing the latest recorded work intervals.
- Most-used projects ranking based on accumulated tracked time.
- Time breakdowns by category, client, and project.
- All summary calculations are based on closed sessions, using paused and completed work intervals.

## Projects

- Project list with search, filtering, sorting, and native macOS navigation.
- Project creation and editing with name, client, daily rate, category, status, tags, and description.
- Project statuses supported: Active, In Progress, Blocked, and Ready.
- Project categories supported: Work and Personal.
- Archive and unarchive actions for keeping inactive projects available without cluttering the active list.
- Favorite project support for faster access from the app workflow.
- Project deletion with confirmation, including removal of associated sessions.
- Project detail view with client, description, tags, status, category, daily rate, accumulated time, and accumulated value.
- Built-in project timer controls to start, pause, and stop tracked work.
- One active timer rule: starting a timer for a project closes the currently running interval before creating a new one.
- Manual session creation and session editing for corrections or backfilled time entries.
- Session deletion from the project detail screen.
- Project comments with author, timestamp, and delete support.
- Estimated project value calculation based on the configured daily rate and an 8-hour standard workday.

## Reports

- Report screen with filters for period, project, category, session status, client, and tag.
- Supported report periods: today, yesterday, current week, current month, current year, and custom date ranges.
- Detailed report mode with one row per tracked session.
- Grouped report mode by project and day, consolidating duration, estimated value, notes, and session count.
- Configurable report columns, including project, client, date, start time, end time, duration, session count, category, status, value, note, tags, and description.
- Saved report presets for reusing column selections and grouping mode.
- Preset management with save, apply, and delete actions.
- Report totals for tracked duration and estimated value.
- Export support for CSV, Excel-compatible XML, and PDF.
- Exported reports use the currently selected filters, grouping mode, and visible columns.

## Billing

- Billing screen for generating invoices from tracked project sessions.
- Client-based invoice generation using the clients already registered in projects.
- Billing periods aligned with report periods, including custom date ranges.
- Invoice preview table grouped by project and day.
- Preview totals for billable duration and estimated value before invoice generation.
- Invoice notes support.
- Overlap detection to prevent generating multiple invoices for the same client and overlapping period.
- Sequential invoice numbering using the `FAT-0001` format.
- Invoice history with number, client, period, value, and status.
- Invoice status toggle between Pending and Paid.
- Invoice deletion from the billing history.
- PDF export for generated invoices.
- Invoice PDFs include issuer information from settings, invoice number, issue date, client, billing period, line items, totals, notes, and WorkLog footer.
