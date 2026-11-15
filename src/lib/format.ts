export function compact(n: number) {
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(n >= 10_000_000 ? 0 : 1).replace(/\.0$/, '') + 'M';
  if (n >= 10_000) return Math.round(n / 1000) + 'K';
  if (n >= 1000) return (n / 1000).toFixed(1).replace(/\.0$/, '') + 'K';
  return String(n);
}

export function likedPercent(likes: number, dislikes: number) {
  const total = likes + dislikes;
  return total === 0 ? null : Math.round((likes / total) * 100);
}

export function players(min: number, max: number) {
  if (min === max) return `${min} player${min === 1 ? '' : 's'}`;
  if (max - min === 1) return `${min} or ${max} players`;
  return `${min} to ${max} players`;
}

export function score(value: number, unit: string) {
  const text = Number.isInteger(value) ? value.toLocaleString('en-US') : value.toFixed(1);
  if (unit === '%') return text + '%';
  if (unit === 'm') return text + ' m';
  return text;
}

/** The unit as a word after a score: "1 floor", "3 floors". Percent and metres are already part of the score. */
export function unitWord(value: number, unit: string) {
  if (unit === '%' || unit === 'm') return '';
  return value === 1 && unit.endsWith('s') ? unit.slice(0, -1) : unit;
}

export function duration(ms: number) {
  const seconds = Math.round(ms / 1000);
  if (seconds < 60) return `${seconds}s`;
  return `${Math.floor(seconds / 60)}m ${String(seconds % 60).padStart(2, '0')}s`;
}

export function ago(at: number, now: number) {
  const minutes = Math.max(0, Math.floor((now - at) / 60000));
  if (minutes < 1) return 'now';
  if (minutes < 60) return `${minutes}m`;
  if (minutes < 1440) return `${Math.floor(minutes / 60)}h`;
  return `${Math.floor(minutes / 1440)}d`;
}

export function untilMidnight(now: Date) {
  const midnight = new Date(now);
  midnight.setHours(24, 0, 0, 0);
  const minutes = Math.max(1, Math.round((midnight.getTime() - now.getTime()) / 60000));
  return minutes >= 60 ? `${Math.floor(minutes / 60)}h ${minutes % 60}m` : `${minutes}m`;
}
