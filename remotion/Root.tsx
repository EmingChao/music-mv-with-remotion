import React from 'react';
import {Composition} from 'remotion';
import {MV} from './MV';
import proj from './project.gen.json';

export const RemotionRoot: React.FC = () => {
  const p = proj as any;
  return (
    <Composition
      id="MV"
      component={MV}
      durationInFrames={Math.max(1, Math.round(p.duration * p.fps))}
      fps={p.fps}
      width={p.ow}
      height={p.oh}
    />
  );
};
