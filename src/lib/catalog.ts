export type CatalogEntry = {
  cover: number;
  icon: number;
  tint: string;
};

export const catalog: Record<string, CatalogEntry> = {
  'tippy-tower': {
    cover: require('@/assets/games/tippy-tower-cover.png'),
    icon: require('@/assets/games/tippy-tower-icon.png'),
    tint: '#3B2A78',
  },
  'five-up': {
    cover: require('@/assets/games/five-up-cover.png'),
    icon: require('@/assets/games/five-up-icon.png'),
    tint: '#EADFC8',
  },
  'spiral-drop': {
    cover: require('@/assets/games/spiral-drop-cover.png'),
    icon: require('@/assets/games/spiral-drop-icon.png'),
    tint: '#12788C',
  },
  'gulp-city': {
    cover: require('@/assets/games/gulp-city-cover.png'),
    icon: require('@/assets/games/gulp-city-icon.png'),
    tint: '#B9B8E6',
  },
  inkland: {
    cover: require('@/assets/games/inkland-cover.png'),
    icon: require('@/assets/games/inkland-icon.png'),
    tint: '#181C50',
  },
  'lane-dash': {
    cover: require('@/assets/games/lane-dash-cover.png'),
    icon: require('@/assets/games/lane-dash-icon.png'),
    tint: '#6B2A8C',
  },
};

export type Clip = { id: string; slug: string; author: string; caption: string; seed: number };

export const clips: Clip[] = [
  { id: 'c1', slug: 'tippy-tower', author: 'devon.plays', caption: 'nine perfect drops in a row, then this', seed: 11 },
  { id: 'c2', slug: 'lane-dash', author: 'noor.runs', caption: 'the near miss at the end. I stopped breathing', seed: 23 },
  { id: 'c3', slug: 'spiral-drop', author: 'kaz', caption: 'eleven floors without touching red', seed: 5 },
  { id: 'c4', slug: 'gulp-city', author: 'tofu', caption: 'swallowed the whole block with two seconds left', seed: 42 },
  { id: 'c5', slug: 'five-up', author: 'wordnerd.sam', caption: 'got it in five. my group chat is furious', seed: 8 },
  { id: 'c6', slug: 'inkland', author: 'juno', caption: 'took a fifth of the map in one loop', seed: 17 },
  { id: 'c7', slug: 'tippy-tower', author: 'kaz', caption: 'slow and steady until floor twenty', seed: 61 },
  { id: 'c8', slug: 'spiral-drop', author: 'juno', caption: 'triple combo on level two', seed: 77 },
  { id: 'c9', slug: 'lane-dash', author: 'devon.plays', caption: 'ramp, three gems, barrier. classic', seed: 91 },
  { id: 'c10', slug: 'gulp-city', author: 'noor.runs', caption: 'started with a flower, ended with a bus', seed: 104 },
  { id: 'c11', slug: 'inkland', author: 'tofu', caption: 'one step from home and still made it', seed: 131 },
  { id: 'c12', slug: 'five-up', author: 'kaz', caption: 'second guess was a gift', seed: 150 },
];
