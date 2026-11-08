// Reads the crash report that a failed native run prints to stderr (src/report.zig).

/** Returns the report's reason, its first line, or '' when stderr holds no report. */
export function crashReason(stderr) {
  return (stderr ?? '').split('\n')[0];
}
