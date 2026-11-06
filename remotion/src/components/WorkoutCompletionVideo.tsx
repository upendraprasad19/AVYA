import React from 'react';
import {
  AbsoluteFill,
  spring,
  useCurrentFrame,
  useVideoConfig,
  interpolate,
} from 'remotion';
import { theme, dmSans, fontUrl } from '../utils/theme';
import { formatVolume, formatDuration } from '../utils/format';

export interface WorkoutCompletionProps {
  userName: string;
  exercises: Array<{ name: string; sets: number; reps: number; weight: number }>;
  totalVolume: number;
  durationSeconds: number;
  streakWeeks: number;
  newPrs: string[];
  tagline: string;
}

export const WorkoutCompletionVideo: React.FC<WorkoutCompletionProps> = ({
  userName,
  exercises,
  totalVolume,
  durationSeconds,
  streakWeeks,
  newPrs,
  tagline,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const headerSpring = spring({ frame, fps, config: { damping: 15, stiffness: 100 } });
  const statsSpring = spring({ frame: frame - 15, fps, config: { damping: 12, stiffness: 80 }, durationInFrames: 45 });
  const exerciseOpacity = interpolate(frame, [30, 50], [0, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' });
  const taglineOpacity = interpolate(frame, [90, 110], [0, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' });
  const qrOpacity = interpolate(frame, [130, 150], [0, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' });

  return (
    <AbsoluteFill style={{ backgroundColor: theme.bg, fontFamily: dmSans }}>
      <style>{`@import url('${fontUrl}');`}</style>

      {/* Top cyan accent line */}
      <div style={{
        position: 'absolute', top: 0, left: 0, right: 0, height: 4,
        background: `linear-gradient(90deg, ${theme.accent}, transparent)`,
      }} />

      {/* Header */}
      <div style={{
        transform: `translateY(${interpolate(headerSpring, [0, 1], [-60, 0])}px)`,
        opacity: headerSpring,
        padding: '80px 48px 0',
      }}>
        <div style={{ fontSize: 13, fontWeight: 700, letterSpacing: '2px', color: theme.accent, marginBottom: 8 }}>
          WORKOUT COMPLETE
        </div>
        <div style={{ fontSize: 40, fontWeight: 900, color: theme.textPrimary }}>
          {userName}
        </div>
        {streakWeeks > 0 && (
          <div style={{
            display: 'inline-flex', alignItems: 'center', gap: 6,
            background: 'rgba(0,212,255,0.08)', border: '1px solid rgba(0,212,255,0.2)',
            borderRadius: 100, padding: '4px 12px', marginTop: 12,
          }}>
            <span style={{ fontSize: 16 }}>🔥</span>
            <span style={{ fontSize: 13, fontWeight: 900, color: theme.accent }}>
              {streakWeeks} Week Streak
            </span>
          </div>
        )}
      </div>

      {/* Stats Row */}
      <div style={{
        display: 'flex', gap: 16, padding: '40px 48px 0',
        opacity: statsSpring,
        transform: `translateY(${interpolate(statsSpring, [0, 1], [30, 0])}px)`,
      }}>
        {[
          { label: 'VOLUME', value: formatVolume(totalVolume) },
          { label: 'DURATION', value: formatDuration(durationSeconds) },
          { label: 'EXERCISES', value: String(exercises.length) },
        ].map((stat) => (
          <div key={stat.label} style={{
            flex: 1, background: theme.card, borderRadius: 16,
            border: `1px solid ${theme.border}`, padding: '16px 12px', textAlign: 'center',
          }}>
            <div style={{ fontSize: 10, fontWeight: 700, letterSpacing: '1px', color: theme.textSecondary, marginBottom: 6 }}>
              {stat.label}
            </div>
            <div style={{ fontSize: 28, fontWeight: 900, color: theme.textPrimary }}>
              {stat.value}
            </div>
          </div>
        ))}
      </div>

      {/* PRs */}
      {newPrs.length > 0 && (
        <div style={{ opacity: exerciseOpacity, padding: '24px 48px 0' }}>
          <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: '1.2px', color: theme.proGold, marginBottom: 10 }}>
            🏆 NEW PERSONAL RECORDS
          </div>
          {newPrs.slice(0, 2).map((pr) => (
            <div key={pr} style={{
              background: 'rgba(245,158,11,0.08)', border: '1px solid rgba(245,158,11,0.2)',
              borderRadius: 12, padding: '8px 14px', marginBottom: 6,
              fontSize: 14, fontWeight: 700, color: theme.proGold,
            }}>
              {pr}
            </div>
          ))}
        </div>
      )}

      {/* Exercise List */}
      <div style={{ opacity: exerciseOpacity, padding: '20px 48px 0' }}>
        <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: '1.2px', color: theme.textSecondary, marginBottom: 10 }}>
          EXERCISES
        </div>
        {exercises.slice(0, 4).map((ex, i) => (
          <div key={i} style={{
            display: 'flex', justifyContent: 'space-between', alignItems: 'center',
            padding: '8px 0', borderBottom: `1px solid ${theme.border}`,
          }}>
            <div style={{ fontSize: 14, color: theme.textPrimary, fontWeight: 500 }}>{ex.name}</div>
            <div style={{ fontSize: 13, color: theme.textSecondary }}>
              {ex.sets}×{ex.reps}{ex.weight > 0 ? ` @ ${ex.weight}kg` : ''}
            </div>
          </div>
        ))}
      </div>

      {/* Tagline */}
      <div style={{
        opacity: taglineOpacity, padding: '32px 48px 0',
        fontSize: 18, fontWeight: 800, fontStyle: 'italic',
        color: theme.accent, lineHeight: 1.3,
      }}>
        "{tagline}"
      </div>

      {/* Footer */}
      <div style={{
        position: 'absolute', bottom: 80, left: 48, right: 48,
        opacity: qrOpacity, display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      }}>
        <div>
          <div style={{ fontSize: 18, fontWeight: 900, color: theme.textPrimary, letterSpacing: '1px' }}>
            ICANBEFITTER
          </div>
          <div style={{ fontSize: 11, color: theme.textSecondary }}>www.icanbefitter.com</div>
        </div>
        <div style={{
          width: 64, height: 64, background: theme.card,
          border: `1px solid ${theme.border}`, borderRadius: 8,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontSize: 10, color: theme.textSecondary,
        }}>
          QR
        </div>
      </div>
    </AbsoluteFill>
  );
};
