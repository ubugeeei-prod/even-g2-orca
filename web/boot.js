// Load the official Even Hub SDK before the MoonBit app. Outside the Even App
// the SDK may be missing or never connect; the app then runs as a preview.
try {
  globalThis.EvenHubSdk = await import('./even_hub_sdk.js');
} catch (error) {
  console.warn('Even Hub SDK unavailable', error);
}
await import('./app.js');
