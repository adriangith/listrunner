import { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'ai.listrunner.app',
  appName: 'ListRunner',
  webDir: 'dist',
  bundledWebRuntime: false,
  plugins: {
    Preferences: {
      group: 'group.ai.listrunner.app'
    }
  }
};

export default config;
