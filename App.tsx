// @ts-ignore
import App from '@@app';
import { useEffect, useState } from 'react';
import { AppState, Linking } from 'react-native';
import BootSplash from 'react-native-bootsplash';
import * as Updates from 'rn-shell-updates';

import runtimeConfig from './.runtime.config.json';

const { deepLink } = runtimeConfig;

// Plugins (rn-shell-updates): which there are, and where the app is (development loads them from Metro)
Updates.configurePlugins(runtimeConfig);


export function ShellApp() {
  const [path, setPath] = useState<string | null>(null);

  useEffect(() => {
    function parseUrl(url: string) {
      if (url.startsWith('https://') || url.startsWith('http://')) {
        const idx = url.indexOf('/', 9);
        if (idx >= 0) {
          return(url.substring(idx));
        } else {
          return('/');
        }
      } else if (url.startsWith(`${deepLink}://`)) {
        return(url.substring(deepLink.length + 2));
      } else {
        return null;
      }
    }

    // Check if there is something to link to
    Linking.getInitialURL().then((res) => {
      const parsed = res && parseUrl(res);
      setPath(parsed ? parsed : '/');
      BootSplash.hide({ fade: true });
    });

    const subscription = Linking.addEventListener('url', (res) => {
      console.log('got link event', res.url);
      const parsed = parseUrl(res.url);
      if (parsed) setPath(parsed);
    });

    return () => {
      subscription.remove();
    }
  }, []);

  // Over the air updates: the app rendered, so a new update is kept; then look
  // for a newer one (at launch, and back in the foreground at most every 15
  // minutes), started on the next launch
  useEffect(() => {
    if (path === null) return;
    Updates.ready();
    let last = 0;
    function check() {
      if (Date.now() - last < 15 * 60_000) return;
      last = Date.now();
      Updates.check().then((result) => {
        if (result.status === 'downloaded' || result.status === 'failed') console.log('[updates]', result);
      });
    }
    check();
    const subscription = AppState.addEventListener('change', (state) => {
      if (state === 'active') check();
    });
    return () => subscription.remove();
  }, [path !== null]);

  if (path === null) return null;
  return <App path={path}  />
}
