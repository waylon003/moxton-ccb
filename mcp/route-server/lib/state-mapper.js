export function mapRouteToLockState(status, workerName) {
  const s = (status || '').toLowerCase();
  if (s === 'success') {
    return workerName.includes('-qa') ? 'qa_passed' : 'waiting_qa';
  }
  if (s === 'fail' || s === 'blocked') return 'blocked';
  if (s === 'in_progress') return 'in_progress';
  return s;
}
