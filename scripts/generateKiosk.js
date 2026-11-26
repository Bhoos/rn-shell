/**
 * Kiosk mode for iOS, configured in the application package.json:
 *
 *   "rn-shell": {
 *     "kiosk": true                                     // full screen + keep awake
 *     "kiosk": { "fullScreen": true, "keepAwake": false } // or pick individually
 *   }
 *
 * Runs as an Xcode build phase and writes into the built Info.plist:
 *  - fullScreen: hides the status bar and opts out of iPad multitasking
 *    (UIRequiresFullScreen). RNShellFullScreen tells the AppDelegate to also
 *    auto hide the home indicator.
 *  - keepAwake: RNShellKeepAwake tells the AppDelegate to disable the idle timer.
 *
 * Every key is always written, so turning kiosk mode off restores normal behaviour.
 *
 * Locking the device to the app (Guided Access / Single App Mode) is a device
 * setting or MDM policy and can't be enabled from the app itself.
 */
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

function plist(infoPlist, ...args) {
  execFileSync('plutil', [...args, infoPlist]);
}

function generateKiosk(infoPlist, kiosk) {
  const fullScreen = Boolean(kiosk && kiosk.fullScreen);
  const keepAwake = Boolean(kiosk && kiosk.keepAwake);

  console.log(`Kiosk mode: fullScreen=${fullScreen}, keepAwake=${keepAwake}`);

  plist(infoPlist, '-replace', 'RNShellFullScreen', '-bool', String(fullScreen));
  plist(infoPlist, '-replace', 'RNShellKeepAwake', '-bool', String(keepAwake));
  plist(infoPlist, '-replace', 'UIStatusBarHidden', '-bool', String(fullScreen));
  plist(infoPlist, '-replace', 'UIRequiresFullScreen', '-bool', String(fullScreen));
}

module.exports = { generateKiosk };

// Run as an Xcode build phase script
if (require.main === module) {
  const config = JSON.parse(fs.readFileSync(path.resolve(process.env.SRCROOT, '../.runtime.config.json')));
  const infoPlist = `${process.env.BUILT_PRODUCTS_DIR}/${process.env.INFOPLIST_PATH}`;
  try {
    generateKiosk(infoPlist, config.kiosk);
  } catch (err) {
    console.error(`error: ${err.message}`);
    process.exit(1);
  }
}
