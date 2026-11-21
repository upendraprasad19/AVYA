import React from 'react';
import { Composition } from 'remotion';
import { WorkoutCompletionVideo, WorkoutCompletionProps } from './components/WorkoutCompletionVideo';
import { WeeklyRecapVideo, WeeklyRecapProps } from './components/WeeklyRecapVideo';

const defaultWorkoutProps: WorkoutCompletionProps = {
  userName: 'Upendra',
  exercises: [
    { name: 'Bench Press', sets: 4, reps: 8, weight: 80 },
    { name: 'Pull Ups', sets: 3, reps: 10, weight: 0 },
    { name: 'Squats', sets: 4, reps: 6, weight: 100 },
  ],
  totalVolume: 4200,
  durationSeconds: 2700,
  streakWeeks: 6,
  newPrs: ['Bench Press'],
  tagline: "Your muscles called. They said 'more please'.",
};

const defaultWeeklyProps: WeeklyRecapProps = {
  userName: 'Upendra',
  weekNumber: 8,
  totalVolume: 18400,
  totalWorkouts: 4,
  totalPrs: 2,
  dailyVolumes: [4200, 0, 5100, 3800, 0, 5300, 0],
  topExercises: [
    { name: 'Bench Press', maxWeight: 85, sets: 16 },
    { name: 'Deadlift', maxWeight: 120, sets: 12 },
    { name: 'Pull Ups', maxWeight: 0, sets: 15 },
  ],
  aiTagline: 'You lifted more than last week. Keep this momentum.',
};

export const RemotionRoot: React.FC = () => (
  <>
    <Composition
      id="WorkoutCompletion"
      component={WorkoutCompletionVideo}
      durationInFrames={180}
      fps={30}
      width={1080}
      height={1920}
      defaultProps={defaultWorkoutProps}
    />
    <Composition
      id="WeeklyRecap"
      component={WeeklyRecapVideo}
      durationInFrames={540}
      fps={30}
      width={1080}
      height={1920}
      defaultProps={defaultWeeklyProps}
    />
  </>
);
