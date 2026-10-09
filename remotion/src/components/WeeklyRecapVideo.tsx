import React from 'react';
import {
  AbsoluteFill,
  spring,
  useCurrentFrame,
  useVideoConfig,
  interpolate,
  Sequence,
} from 'remotion';
import { theme, dmSans, fontUrl } from '../utils/theme';
import { formatVolume } from '../utils/format';

export interface WeeklyRecapProps {
  userName: string;
  weekNumber: number;
  /**
   * 1-based free-tier hold number (H1, H2 ...) when the recapped week was a
   * "Hold the Line" week, else omitted. A hold week sits outside the phase's
   * four weeks, so `weekNumber` clamps to 4 for every hold at every ordinal —
   * "WEEK 4 RECAP" forever. When present this supersedes the week counter
   * (FOB-1 / OI-60). Optional, so a caller that omits it renders exactly as
   * before.
   */
  holdOrdinal?: number;
  totalVolume: number;
  totalWorkouts: number;
  totalPrs: number;
  dailyVolumes: number[]; // 7 values Mon–Sun
  topExercises: Array<{ name: string; maxWeight: number; sets: number }>;
  aiTagline: string;
}

export const WeeklyRecapVideo: React.FC<WeeklyRecapProps> = ({
  userName,
  weekNumber,
  holdOrdinal,
  totalVolume,
  totalWorkouts,
  totalPrs,
  dailyVolumes,
  topExercises,
  aiTagline,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const maxVolume = Math.max(...dailyVolumes, 1);
  const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  return (
    <AbsoluteFill style={{ backgroundColor: theme.bg, fontFamily: dmSans }}>
      <style>{`@import url('${fontUrl}');`}</style>

      {/* Persistent header */}
      <div style={{ padding: '80px 48px 0' }}>
        <div style={{ fontSize: 12, fontWeight: 700, letterSpacing: '2px', color: theme.accent }}>
          {holdOrdinal == null ? `WEEK ${weekNumber} RECAP` : `HOLD H${holdOrdinal} RECAP`}
        </div>
        <div style={{ fontSize: 36, fontWeight: 900, color: theme.textPrimary, marginTop: 6 }}>
          {userName}
        </div>
      </div>

      {/* Stats */}
      <Sequence from={15} durationInFrames={540}>
        <div style={{
          display: 'flex', gap: 12, padding: '32px 48px 0',
          opacity: interpolate(frame, [15, 35], [0, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' }),
        }}>
          {[
            { label: 'VOLUME', value: formatVolume(totalVolume), color: theme.accent },
            { label: 'WORKOUTS', value: String(totalWorkouts), color: theme.green },
            { label: 'NEW PRs', value: String(totalPrs), color: theme.proGold },
          ].map((s) => (
            <div key={s.label} style={{
              flex: 1, background: theme.card, borderRadius: 14,
              border: `1px solid ${theme.border}`, padding: '14px 10px', textAlign: 'center',
            }}>
              <div style={{ fontSize: 9, fontWeight: 700, letterSpacing: '1px', color: theme.textSecondary }}>{s.label}</div>
              <div style={{ fontSize: 24, fontWeight: 900, color: s.color, marginTop: 4 }}>{s.value}</div>
            </div>
          ))}
        </div>
      </Sequence>

      {/* Bar Chart */}
      <Sequence from={60} durationInFrames={480}>
        <div style={{ padding: '32px 48px 0' }}>
          <div style={{ fontSize: 10, fontWeight: 700, letterSpacing: '1.2px', color: theme.textSecondary, marginBottom: 16 }}>
            DAILY VOLUME
          </div>
          <div style={{ display: 'flex', gap: 8, alignItems: 'flex-end', height: 120 }}>
            {dailyVolumes.map((vol, i) => {
              const barProgress = spring({
                frame: frame - 60 - i * 8,
                fps,
                config: { damping: 20, stiffness: 100 },
              });
              const barHeight = interpolate(barProgress, [0, 1], [0, (vol / maxVolume) * 100]);
              return (
                <div key={i} style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6 }}>
                  <div style={{
                    width: '100%', height: `${barHeight}%`,
                    background: vol > 0 ? theme.accent : theme.border,
                    borderRadius: '4px 4px 0 0', minHeight: 4,
                    boxShadow: vol > 0 ? `0 0 8px rgba(0,212,255,0.3)` : 'none',
                  }} />
                  <div style={{ fontSize: 10, color: theme.textSecondary }}>{days[i]}</div>
                </div>
              );
            })}
          </div>
        </div>
      </Sequence>

      {/* Top Exercises */}
      <Sequence from={180} durationInFrames={360}>
        <div style={{
          padding: '28px 48px 0',
          opacity: interpolate(frame, [180, 210], [0, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' }),
        }}>
          <div style={{ fontSize: 10, fontWeight: 700, letterSpacing: '1.2px', color: theme.textSecondary, marginBottom: 12 }}>
            TOP LIFTS
          </div>
          {topExercises.slice(0, 3).map((ex, i) => (
            <div key={i} style={{
              display: 'flex', justifyContent: 'space-between',
              padding: '10px 0', borderBottom: `1px solid ${theme.border}`,
            }}>
              <div style={{ fontSize: 14, color: theme.textPrimary, fontWeight: 600 }}>{ex.name}</div>
              <div style={{ fontSize: 13, color: theme.accent, fontWeight: 700 }}>
                {ex.maxWeight > 0 ? `${ex.maxWeight}kg` : `${ex.sets} sets`}
              </div>
            </div>
          ))}
        </div>
      </Sequence>

      {/* AI Tagline */}
      <Sequence from={360} durationInFrames={180}>
        <div style={{
          padding: '32px 48px 0',
          opacity: interpolate(frame, [360, 390], [0, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' }),
          fontSize: 16, fontWeight: 700, fontStyle: 'italic',
          color: theme.accent, lineHeight: 1.4,
        }}>
          "{aiTagline}"
        </div>
      </Sequence>

      {/* Footer */}
      <div style={{
        position: 'absolute', bottom: 64, left: 48, right: 48,
        display: 'flex', justifyContent: 'space-between', alignItems: 'center',
        opacity: interpolate(frame, [440, 460], [0, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' }),
      }}>
        <div style={{ fontSize: 16, fontWeight: 900, color: theme.textPrimary }}>ICANBEFITTER</div>
        <div style={{ fontSize: 10, color: theme.textSecondary }}>www.icanbefitter.com</div>
      </div>
    </AbsoluteFill>
  );
};
